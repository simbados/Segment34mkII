import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

// Sitting/walking state shared by the face and the stand-up reminder service. Both run
// in the same app, so the state is kept in Application.Storage: the face updates it
// about once a minute, the service whenever it runs (e.g. while another app is open).
//
// lastMove is the time of the last movement (the step count rose by at least the
// movement threshold since the previous movement), so a few fidgeting steps do not
// count. A walk starts at the first movement after a pause of ACTIVE_GAP_SEC and ends
// at its last movement, so both durations are backdated.
//
// Example (threshold 10, gap 2 min), sampled each minute:
//   10:00 1200 (start)  10:20 1205  -> inactive 20, active 0
//   10:21 1260 (walk starts)  10:26 1700 (last steps)  -> inactive 0, active 5
//   10:30 1702 (sitting again) -> inactive 4, active 5 (last walk)
(:background)
module ActivityTracker {
    const ACTIVE_GAP_SEC = 120;
    const MIN_EVENT_GAP_SEC = 300;  // Garmin: background events at least 5 minutes apart
    const QUIET_FROM_HOUR = 22;     // no reminders from 22:00 ...
    const QUIET_TO_HOUR = 7;        // ... until 07:00
    const QUIET_RECHECK_SEC = 1800;

    var baseSteps as Number = -1;
    var lastMove as Number = 0;
    var activeStart as Number = 0;
    var loaded as Boolean = false;

    function reload() as Void {
        var s = Application.Storage.getValue("activity");
        if(s instanceof Array && s.size() == 3) {
            baseSteps = s[0] as Number;
            lastMove = s[1] as Number;
            activeStart = s[2] as Number;
        } else {
            baseSteps = -1;
        }
        loaded = true;
    }

    function save() as Void {
        Application.Storage.setValue("activity", [baseSteps, lastMove, activeStart] as Array<Application.PropertyValueType>);
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

    // Samples the step count. Returns true if the state changed.
    function update() as Boolean {
        if(!loaded) { reload(); }
        var steps = ActivityMonitor.getInfo().steps;
        if(steps == null) { return false; }
        var now = Time.now().value();
        if(baseSteps < 0) { // first sample
            baseSteps = steps;
            lastMove = now;
            activeStart = now;
        } else if(steps < baseSteps) { // step counter reset at midnight
            baseSteps = steps;
        } else if(steps - baseSteps >= threshold()) {
            if(now - lastMove >= ACTIVE_GAP_SEC) { activeStart = now; } // a new walk begins
            baseSteps = steps;
            lastMove = now;
        } else {
            return false;
        }
        save();
        return true;
    }

    function inactiveMinutes() as Number {
        if(!loaded) { reload(); }
        return (baseSteps < 0) ? 0 : (Time.now().value() - lastMove) / 60;
    }

    // Duration of the current walk, or of the last one while sitting.
    function activeMinutes() as Number {
        if(!loaded) { reload(); }
        if(baseSteps < 0) { return 0; }
        var now = Time.now().value();
        var end = (now - lastMove < ACTIVE_GAP_SEC) ? now : lastMove;
        return (end - activeStart) / 60;
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
