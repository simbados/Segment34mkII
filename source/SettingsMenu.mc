import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// On-watch settings menu for the settings listed in SettingsMenuData. The main menu
// shows each setting with its current value; selecting one opens its option list.
// Option lists are JSON resources loaded only while needed, to keep memory low.
class SettingsMenu extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({:title => "Settings"});
        var items = SettingsMenuData.items();
        for (var i = 0; i < items.size(); i++) {
            var key = items[i][0] as String;
            var options = WatchUi.loadResource(items[i][2] as ResourceId) as Array<Array>;
            addItem(new WatchUi.MenuItem(items[i][1] as String,
                SettingsMenuOptions.labelFor(options, Application.Properties.getValue(key) as Number), i, {}));
        }
    }
}

class SettingsMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var entry = SettingsMenuData.items()[item.getId() as Number];
        var key = entry[0] as String;
        var options = WatchUi.loadResource(entry[2] as ResourceId) as Array<Array>;
        var current = Application.Properties.getValue(key) as Number;

        var menu = new WatchUi.Menu2({:title => entry[1] as String});
        for (var i = 0; i < options.size(); i++) {
            menu.addItem(new WatchUi.MenuItem(options[i][1] as String, null, options[i][0] as Number, {}));
            if (options[i][0] == current) {
                menu.setFocus(i);
            }
        }
        WatchUi.pushView(menu, new SettingsOptionDelegate(key, item), WatchUi.SLIDE_LEFT);
    }
}

// Saves the chosen option, updates the parent menu item and redraws the face.
class SettingsOptionDelegate extends WatchUi.Menu2InputDelegate {
    private var _key as String;
    private var _parent as WatchUi.MenuItem;

    function initialize(key as String, parent as WatchUi.MenuItem) {
        Menu2InputDelegate.initialize();
        _key = key;
        _parent = parent;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        Application.Properties.setValue(_key, item.getId() as Number);
        _parent.setSubLabel(item.getLabel());
        getApp().onSettingsChanged();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

module SettingsMenuOptions {
    // Example: labelFor([[0, "Hidden"], [1, "Stress"]], 1) -> "Stress"
    function labelFor(options as Array<Array>, value as Number?) as String {
        for (var i = 0; i < options.size(); i++) {
            if (options[i][0] == value) {
                return options[i][1] as String;
            }
        }
        return (value == null) ? "" : value.toString();
    }
}
