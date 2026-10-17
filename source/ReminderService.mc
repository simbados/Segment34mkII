import Toybox.Background;
import Toybox.Lang;
import Toybox.Notifications;
import Toybox.System;
import Toybox.Time;

// Runs at the time ActivityTracker scheduled. If there was no movement since, posts a
// system notification (watch faces may not vibrate themselves) and schedules a repeat;
// otherwise it reschedules for the new reminder time.
(:background)
class ReminderService extends System.ServiceDelegate {
    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        ActivityTracker.reload();
        ActivityTracker.update();
        if(!ActivityTracker.remindersEnabled()) {
            Background.deleteTemporalEvent();
            Background.exit(true);
            return;
        }
        var now = Time.now().value();
        var inactive = ActivityTracker.inactiveMinutes();
        var next;
        if(ActivityTracker.isQuietHour()) {
            next = now + ActivityTracker.QUIET_RECHECK_SEC;
        } else if(inactive * 60 >= ActivityTracker.windowSec() - 30) {
            if(Notifications has :showNotification) {
                Notifications.showNotification("Stand up!", inactive.toString() + " min inactive", {:dismissPrevious => true});
            }
            next = now + ActivityTracker.repeatSec();
        } else {
            next = ActivityTracker.lastMove + ActivityTracker.windowSec();
        }
        ActivityTracker.scheduleAt(next);
        Background.exit(true);
    }
}
