import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.Notifications;
import Toybox.System;
import Toybox.Time;

// Runs at the time ActivityTracker scheduled, at least every few minutes, and samples the
// steps. When the inactive time reaches the window it posts a system notification (watch
// faces may not vibrate themselves), and again every repeat interval while still sitting.
(:background)
class ReminderService extends System.ServiceDelegate {
    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        ActivityTracker.reload();
        ActivityTracker.update("svc");
        if(!ActivityTracker.remindersEnabled()) {
            Background.deleteTemporalEvent();
            Background.exit(true);
            return;
        }
        var now = Time.now().value();
        var inactive = ActivityTracker.inactiveMinutes();
        var next;
        var notifiedNow = false;
        if(ActivityTracker.isQuietHour()) {
            next = now + ActivityTracker.QUIET_RECHECK_SEC;
        } else {
            // a reminder is due when the window is reached, then every repeat interval;
            // reminders sent before the last movement do not count
            var due = ActivityTracker.lastMove + ActivityTracker.windowSec();
            var notified = Application.Storage.getValue("lastNotify");
            if(notified instanceof Number && notified > ActivityTracker.lastMove) {
                due = notified + ActivityTracker.repeatSec();
            }
            if(now >= due - 30) {
                if(Notifications has :showNotification) {
                    Notifications.showNotification("Stand up!", inactive.toString() + " min inactive", {:dismissPrevious => true});
                }
                Application.Storage.setValue("lastNotify", now);
                notifiedNow = true;
                due = now + ActivityTracker.repeatSec();
            }
            // wake up again at least every few minutes to sample the steps
            next = (due < now + ActivityTracker.SAMPLE_EVERY_SEC) ? due : now + ActivityTracker.SAMPLE_EVERY_SEC;
        }
        ActivityTracker.scheduleAt(next);
        ActivityTracker.log("svc", "R inactive=" + inactive + " notified=" + (notifiedNow ? 1 : 0) + " next=" + ActivityTracker.hms(next));
        Background.exit(true);
    }
}
