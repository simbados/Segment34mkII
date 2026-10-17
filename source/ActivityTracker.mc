import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

// Sitting/walking state shared by the face and the stand-up reminder service. Both run
// in the same app, so the state is kept in Application.Storage: the face samples the
// step count about once a minute (not at all while the screen is off), the service
// whenever it runs.
//
// The watch only tells us the step total, not when the steps happened, so the time of
// a movement is estimated from the steps taken since the previous sample: d steps take
// d / CADENCE minutes (at most the time since the previous sample). A sample with at
// least `threshold` new steps is a movement; fewer steps (fidgeting) are ignored.
//   - If the previous sample was also a movement, the new steps continue it
//     (they fill the start of the interval).
//   - Otherwise they are assumed to be right before this sample (you look at the watch
//     while walking or right after).
// A walk starts when the estimated movement begins at least ACTIVE_GAP_SEC after the
// previous movement ended; it ends at the last movement, so both durations are backdated.
//
// Example (threshold 10, cadence 100/min):
//   sitting for hours, then 10:04 sample: 400 new steps -> movement 4 min, walk started
//   10:00 (even though the screen was off the whole time)
//   10:00:10-10:04:10 walk sampled each minute: 10:01 +83 -> started 10:00:10;
//   10:02..10:04 +100 each; 10:05 +17 -> continues 10 s -> ended 10:04:10, active 4 min
(:background)
module ActivityTracker {
    const ACTIVE_GAP_SEC = 120;
    const CADENCE_PER_MIN = 100;    // assumed walking steps per minute
    const MAX_TAIL_SEC = 60;        // the active time may run this long past the last sample
    const MIN_EVENT_GAP_SEC = 300;  // Garmin: background events at least 5 minutes apart
    const QUIET_FROM_HOUR = 22;     // no reminders from 22:00 ...
    const QUIET_TO_HOUR = 7;        // ... until 07:00
    const QUIET_RECHECK_SEC = 1800;

    var baseSteps as Number = -1;   // step count at the previous sample
    var sampleTime as Number = 0;   // time of the previous sample
    var lastMove as Number = 0;
    var activeStart as Number = 0;
    var loaded as Boolean = false;

    function reload() as Void {
        var s = Application.Storage.getValue("activity");
        if(s instanceof Array && s.size() == 4) {
            baseSteps = s[0] as Number;
            sampleTime = s[1] as Number;
            lastMove = s[2] as Number;
            activeStart = s[3] as Number;
        } else {
            baseSteps = -1;
        }
        loaded = true;
    }

    function save() as Void {
        Application.Storage.setValue("activity", [baseSteps, sampleTime, lastMove, activeStart] as Array<Application.PropertyValueType>);
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

    // Samples the step count. Returns true if a movement was detected.
    function update() as Boolean {
        reload(); // the other process (face or service) may have saved in the meantime
        var steps = ActivityMonitor.getInfo().steps;
        if(steps == null) { return false; }
        var now = Time.now().value();
        var moved = false;
        if(baseSteps < 0) { // first sample
            lastMove = now;
            activeStart = now;
        } else if(steps >= baseSteps && steps - baseSteps >= threshold()) {
            var d = steps - baseSteps;
            var dur = d * 60 / CADENCE_PER_MIN;
            if(dur > now - sampleTime) { dur = now - sampleTime; }
            var from;
            if(sampleTime - lastMove <= 15) { // continues the movement of the previous sample
                from = lastMove;
            } else {
                from = now - dur;
                if(from - lastMove >= ACTIVE_GAP_SEC) { activeStart = from; } // a new walk begins
            }
            lastMove = from + dur;
            moved = true;
        }
        baseSteps = steps; // also after a midnight reset (steps < baseSteps)
        sampleTime = now;
        save();
        return moved;
    }

    function inactiveMinutes() as Number {
        if(!loaded) { reload(); }
        return (baseSteps < 0) ? 0 : (Time.now().value() - lastMove) / 60;
    }

    // Duration of the current walk, or of the last one while sitting. Between samples
    // a running walk keeps counting, for at most MAX_TAIL_SEC.
    function activeMinutes() as Number {
        if(!loaded) { reload(); }
        if(baseSteps < 0) { return 0; }
        var tail = Time.now().value() - lastMove;
        if(tail > MAX_TAIL_SEC) { tail = MAX_TAIL_SEC; }
        var end = (Time.now().value() - lastMove < ACTIVE_GAP_SEC) ? lastMove + tail : lastMove;
        return (end - activeStart + 30) / 60;
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

    // Schedules the reminder for when the inactive time reaches the window. If that is
    // already past and the service has scheduled its repeat, the repeat is kept, so
    // returning to the face does not fire an extra reminder.
    function scheduleReminder() as Void {
        var at = lastMove + windowSec();
        var now = Time.now().value();
        if(at <= now) {
            var registered = Background.getTemporalEventRegisteredTime();
            if(registered instanceof Time.Moment && registered.value() > now) { return; }
        }
        scheduleAt(at);
    }
}
