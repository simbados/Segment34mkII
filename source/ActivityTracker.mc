import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

// Sitting/on-feet state shared by the face and the stand-up reminder service. Both run
// in the same app, so the state is kept in Application.Storage: the face samples the
// step count about once a minute while the screen is on, the service at least every
// SAMPLE_EVERY_SEC (Garmin's minimum) while reminders are on.
//
// When in doubt this counts as sitting: resting time is what matters most.
//
// Each sample looks at the interval since the previous one:
//   - Dense samples (at most DENSE_MAX_SEC apart): on feet if this interval has steps and
//     the last ~2 minutes (WINDOW_SEC) have at least `threshold` steps, so slow puttering
//     (5 steps a minute) counts, but a few fidgeting steps do not.
//   - A gap (screen off, no service run): on feet only if at least GAP_MIN_STEPS steps
//     (about 30 s of walking), assumed to be right before this sample.
// The watch only gives the step total, so the time the steps took is estimated as
// steps / CADENCE_PER_MIN, but at least half the interval (slow steps are spread out).
// A bout starts at the first steps of its window and continues
// while the pause between movements is under PAUSE_SEC. A new bout replaces the last one
// shown only once it lasts MIN_BOUT_SEC, so a few steps to the bin do not wipe it.
//
// Example (threshold 10, samples each minute, steps per interval):
//   10:01 +6   window 6   -> sitting
//   10:02 +6   window 12  -> on feet since ~10:01:30 (half of the first interval)
//   10:03 +80, 10:04 +90  -> bout continues; 10:05 +0 -> sitting, end trimmed to ~10:04:54
//   -> active 3 min, bout steps 182
//   12:00 after 2 h without samples: +400 -> bout of 4 min (since 11:56); +30 -> sitting
(:background)
module ActivityTracker {
    const WINDOW_SEC = 150;         // dense samples within this time form the ~2 minute window
    const DENSE_MAX_SEC = 150;      // samples further apart are a gap
    const GAP_MIN_STEPS = 50;       // steps that count as on feet across a gap
    const PAUSE_SEC = 180;          // a longer pause ends the bout
    const MIN_BOUT_SEC = 60;        // a new bout replaces the shown one from this length on
    const CADENCE_PER_MIN = 100;    // assumed walking steps per minute
    const MAX_TAIL_SEC = 60;        // the active time may run this long past the last movement
    const BUFFER_SEC = 300;         // samples kept for the window
    const MIN_SAMPLE_GAP_SEC = 20;  // samples closer than this are skipped
    const SAMPLE_EVERY_SEC = 300;   // background service samples at least this often
    const MIN_EVENT_GAP_SEC = 300;  // Garmin: background events at least 5 minutes apart
    const QUIET_FROM_HOUR = 22;     // no reminders from 22:00 ...
    const QUIET_TO_HOUR = 7;        // ... until 07:00
    const QUIET_RECHECK_SEC = 1800;

    var bufTimes as Array<Number> = [] as Array<Number>;  // recent samples, oldest first
    var bufSteps as Array<Number> = [] as Array<Number>;
    var lastOnFeet as Boolean = false;  // the previous interval was on feet
    var curStart as Number = 0;         // current (or last) bout
    var lastMove as Number = 0;         // end of the current bout = last movement
    var curStartSteps as Number = 0;    // step totals at the bout's start and last movement
    var curEndSteps as Number = 0;
    var prevDur as Number = -1;         // last bout of at least MIN_BOUT_SEC (-1: none)
    var prevSteps as Number = 0;
    var loaded as Boolean = false;

    function reload() as Void {
        var s = Application.Storage.getValue("activity2");
        if(s instanceof Array && s.size() == 9) {
            bufTimes = s[0] as Array<Number>;
            bufSteps = s[1] as Array<Number>;
            lastOnFeet = s[2] as Boolean;
            curStart = s[3] as Number;
            lastMove = s[4] as Number;
            curStartSteps = s[5] as Number;
            curEndSteps = s[6] as Number;
            prevDur = s[7] as Number;
            prevSteps = s[8] as Number;
        } else {
            bufTimes = [] as Array<Number>;
            bufSteps = [] as Array<Number>;
        }
        loaded = true;
    }

    function save() as Void {
        Application.Storage.setValue("activity2", [bufTimes, bufSteps, lastOnFeet, curStart, lastMove,
            curStartSteps, curEndSteps, prevDur, prevSteps] as Array<Application.PropertyValueType>);
    }

    function numberSetting(key as String, fallback as Number) as Number {
        var v = Application.Properties.getValue(key);
        return (v instanceof Number) ? v as Number : fallback;
    }

    function remindersEnabled() as Boolean {
        return Application.Properties.getValue("remindersEnabled") != false;
    }

    function windowSec() as Number { return numberSetting("remindWindowMin", 30) * 60; }
    function repeatSec() as Number { return numberSetting("remindRepeatMin", 5) * 60; }
    function threshold() as Number { return numberSetting("moveThreshold", 10); }

    // Seconds the given steps take at the assumed cadence, at most `limit`.
    function stepSeconds(steps as Number, limit as Number) as Number {
        var dur = steps * 60 / CADENCE_PER_MIN;
        return (dur > limit) ? limit : dur;
    }

    // Samples the step count. Returns true if this sample was on feet.
    function update() as Boolean {
        reload(); // the other process (face or service) may have saved in the meantime
        var steps = ActivityMonitor.getInfo().steps;
        if(steps == null) { return false; }
        var now = Time.now().value();
        var n = bufTimes.size();
        if(n == 0) { // first sample
            bufTimes = [now] as Array<Number>;
            bufSteps = [steps] as Array<Number>;
            curStart = now;
            lastMove = now;
            curStartSteps = steps;
            curEndSteps = steps;
            save();
            return false;
        }
        var tPrev = bufTimes[n - 1];
        if(now - tPrev < MIN_SAMPLE_GAP_SEC) { return false; }
        if(steps < bufSteps[n - 1]) { // step counter reset at midnight: rebase all totals
            var shift = bufSteps[n - 1];
            for(var i = 0; i < n; i++) { bufSteps[i] -= shift; }
            curStartSteps -= shift;
            curEndSteps -= shift;
        }
        var d = steps - bufSteps[n - 1];
        var dt = now - tPrev;

        // from: when the steps of this sample began, fromSteps: step total just before
        var from = -1;
        var fromSteps = bufSteps[n - 1];
        if(dt > DENSE_MAX_SEC) {
            if(d >= GAP_MIN_STEPS) { from = now - stepSeconds(d, dt); }
        } else if(d > 0) {
            // window: the oldest sample within WINDOW_SEC, reached through dense intervals only
            var ref = n - 1;
            while(ref > 0 && bufTimes[ref - 1] >= now - WINDOW_SEC && bufTimes[ref] - bufTimes[ref - 1] <= DENSE_MAX_SEC) { ref--; }
            if(steps - bufSteps[ref] >= threshold()) {
                if(lastOnFeet) {
                    from = tPrev;
                } else {
                    // backdate to the first interval of the window that had steps
                    var first = ref;
                    while(first < n - 1 && bufSteps[first + 1] == bufSteps[first]) { first++; }
                    var t1 = (first < n - 1) ? bufTimes[first + 1] : now;
                    var s1 = (first < n - 1) ? bufSteps[first + 1] : steps;
                    // somewhere in that interval: by the step count, but at least half of
                    // it, since slow steps (puttering) are spread over the whole interval
                    var dur = stepSeconds(s1 - bufSteps[first], t1 - bufTimes[first]);
                    if(dur < (t1 - bufTimes[first]) / 2) { dur = (t1 - bufTimes[first]) / 2; }
                    from = t1 - dur;
                    fromSteps = bufSteps[first];
                }
            }
        }

        if(from >= 0) {
            // on feet until this sample (a walk that ended mid-interval is counted up to
            // a minute too long, but slow puttering is not cut short)
            var to = now;
            if(from - lastMove >= PAUSE_SEC) { // a new bout begins
                if(lastMove - curStart >= MIN_BOUT_SEC || prevDur < 0) {
                    prevDur = lastMove - curStart;
                    prevSteps = curEndSteps - curStartSteps;
                }
                curStart = from;
                curStartSteps = fromSteps;
            }
            if(to > lastMove) { lastMove = to; }
            curEndSteps = steps;
        }
        if(from < 0 && lastOnFeet && n >= 2 && lastMove == tPrev && tPrev - bufTimes[n - 2] <= DENSE_MAX_SEC) {
            // the bout ended in the previous interval: trim its end like its start
            var lastDt = tPrev - bufTimes[n - 2];
            var lastDur = stepSeconds(bufSteps[n - 1] - bufSteps[n - 2], lastDt);
            if(lastDur < lastDt / 2) { lastDur = lastDt / 2; }
            if(bufTimes[n - 2] + lastDur > curStart) { lastMove = bufTimes[n - 2] + lastDur; }
        }
        lastOnFeet = from >= 0;

        bufTimes.add(now);
        bufSteps.add(steps);
        while(bufTimes.size() > 1 && bufTimes[0] < now - BUFFER_SEC) {
            bufTimes = bufTimes.slice(1, null);
            bufSteps = bufSteps.slice(1, null);
        }
        save();
        return lastOnFeet;
    }

    function inactiveMinutes() as Number {
        if(!loaded) { reload(); }
        return (bufTimes.size() == 0) ? 0 : (Time.now().value() - lastMove) / 60;
    }

    // True if the current bout is shown: it is long enough, still going, or the only one.
    function showCurrent() as Boolean {
        return lastMove - curStart >= MIN_BOUT_SEC || prevDur < 0 || lastOnFeet;
    }

    // Duration of the current bout, or of the last one while sitting. While on feet the
    // bout keeps counting between samples, for at most MAX_TAIL_SEC.
    function activeMinutes() as Number {
        if(!loaded) { reload(); }
        if(bufTimes.size() == 0) { return 0; }
        if(!showCurrent()) { return (prevDur + 30) / 60; }
        var tail = lastOnFeet ? Time.now().value() - lastMove : 0;
        if(tail > MAX_TAIL_SEC) { tail = MAX_TAIL_SEC; }
        var end = lastMove + tail;
        return (end - curStart + 30) / 60;
    }

    // Steps of the bout shown by activeMinutes.
    function boutSteps() as Number {
        if(!loaded) { reload(); }
        if(bufTimes.size() == 0) { return 0; }
        return showCurrent() ? curEndSteps - curStartSteps : prevSteps;
    }

    function isQuietHour() as Boolean {
        var hour = System.getClockTime().hour;
        return hour >= QUIET_FROM_HOUR || hour < QUIET_TO_HOUR;
    }

    // Schedules the reminder service at time `at` (unix seconds), or as soon as Garmin
    // allows it (5 minutes after the previous background event).
    //
    // Example: last event 10:28, at = 10:30 -> scheduled for 10:33
    function scheduleAt(at as Number) as Void {
        if(!remindersEnabled()) {
            Background.deleteTemporalEvent();
            return;
        }
        var last = Background.getLastTemporalEventTime();
        if(last != null && at < last.value() + MIN_EVENT_GAP_SEC) {
            at = last.value() + MIN_EVENT_GAP_SEC;
        }
        try {
            Background.registerForTemporalEvent(new Time.Moment(at));
        } catch(e) {
            Background.registerForTemporalEvent(new Time.Moment(Time.now().value() + MIN_EVENT_GAP_SEC));
        }
    }

    // Schedules the service for when the inactive time reaches the window, but at least
    // every SAMPLE_EVERY_SEC so steps are sampled while the screen is off. An earlier
    // event that is already scheduled (e.g. the service's repeat) is kept, so returning to
    // the face does not fire an extra reminder.
    function scheduleReminder() as Void {
        var now = Time.now().value();
        var at = lastMove + windowSec();
        if(at > now + SAMPLE_EVERY_SEC) { at = now + SAMPLE_EVERY_SEC; }
        var registered = Background.getTemporalEventRegisteredTime();
        if(registered instanceof Time.Moment && registered.value() > now && registered.value() <= at) { return; }
        scheduleAt(at);
    }
}
