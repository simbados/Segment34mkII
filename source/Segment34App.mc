import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// :background because the stand-up reminder service runs in this app's background process.
(:background)
class Segment34App extends Application.AppBase {
    
    var mView;
    
    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
    }

    // Return the initial view of your application here
    (:typecheck(disableBackgroundCheck))
    function getInitialView() {
        mView = new Segment34View();
        var delegate = new Segment34Delegate(mView);
        return [mView, delegate];
    }

    (:typecheck(disableBackgroundCheck))
    function onSettingsChanged() as Void {
        ActivityTracker.scheduleReminder();
        if (mView != null) {
            mView.onSettingsChanged();
        }
        WatchUi.requestUpdate();
    }

    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new ReminderService()] as [System.ServiceDelegate];
    }

    // The service changed the shared activity state while the face was running.
    function onBackgroundData(data as Application.PersistableType) as Void {
        ActivityTracker.reload();
    }

    // On-watch settings (long press the watch face, then customize).
    (:typecheck(disableBackgroundCheck))
    function getSettingsView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] or Null {
        return [new SettingsMenu(), new SettingsMenuDelegate()];
    }

}

function getApp() as Segment34App {
    return Application.getApp() as Segment34App;
}