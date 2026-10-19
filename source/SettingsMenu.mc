import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// On-watch settings menu for the settings listed in SettingsMenuData. The main menu
// shows each setting with its current value; selecting one opens its option list.
// Option lists are JSON resources loaded only while needed, to keep memory low.
//
// Both menus are CustomMenus that wrap long text over several lines; the standard
// Menu2 cuts labels off after one line ("Temperature, Wind, Precipi...").
class SettingsMenu extends WatchUi.CustomMenu {
    function initialize() {
        // title on up to 2 lines, current value on up to 2 lines
        CustomMenu.initialize(2 * Graphics.getFontHeight(Graphics.FONT_TINY) + 2 * Graphics.getFontHeight(Graphics.FONT_XTINY) + 12,
            Graphics.COLOR_BLACK, {:title => new SettingsMenuTitle("Settings")});
        var items = SettingsMenuData.items();
        for (var i = 0; i < items.size(); i++) {
            addItem(new WrapMenuItem(i, items[i][1] as String, SettingsMenuOptions.valueLabel(items[i])));
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
        if (entry[2] == null) { // boolean: toggle in place
            Application.Properties.setValue(key, Application.Properties.getValue(key) != true);
            (item as WrapMenuItem).setText(SettingsMenuOptions.valueLabel(entry));
            getApp().onSettingsChanged();
            WatchUi.requestUpdate();
            return;
        }
        var options = WatchUi.loadResource(entry[2] as ResourceId) as Array<Array>;
        var current = Application.Properties.getValue(key) as Number;

        // each option on up to 3 lines
        var menu = new WatchUi.CustomMenu(3 * Graphics.getFontHeight(Graphics.FONT_TINY) + 10, Graphics.COLOR_BLACK,
            {:title => new SettingsMenuTitle(entry[1] as String)});
        for (var i = 0; i < options.size(); i++) {
            menu.addItem(new WrapMenuItem(options[i][0] as Number, null, options[i][1] as String));
            if (options[i][0] == current) {
                menu.setFocus(i);
            }
        }
        WatchUi.pushView(menu, new SettingsOptionDelegate(key, item as WrapMenuItem), WatchUi.SLIDE_LEFT);
    }
}

// Saves the chosen option, updates the parent menu item and redraws the face.
class SettingsOptionDelegate extends WatchUi.Menu2InputDelegate {
    private var _key as String;
    private var _parent as WrapMenuItem;

    function initialize(key as String, parent as WrapMenuItem) {
        Menu2InputDelegate.initialize();
        _key = key;
        _parent = parent;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        Application.Properties.setValue(_key, item.getId() as Number);
        _parent.setText((item as WrapMenuItem).getText());
        getApp().onSettingsChanged();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

// Menu item that wraps its text. With a title (main menu) the title is drawn on up to
// two lines in FONT_TINY and the text (the current value) below in FONT_XTINY; without
// one (option lists) the text uses up to three lines in FONT_TINY. The focused item is
// white, the others gray.
class WrapMenuItem extends WatchUi.CustomMenuItem {
    private var _title as String?;
    private var _text as String;

    function initialize(id as Object, title as String?, text as String) {
        CustomMenuItem.initialize(id, {});
        _title = title;
        _text = text;
    }

    function getText() as String { return _text; }
    function setText(text as String) as Void { _text = text; }

    function draw(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var textWidth = w * 8 / 10; // round screen: keep away from the edges
        dc.setColor(isFocused() ? Graphics.COLOR_WHITE : Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        if (_title == null) {
            drawWrapped(dc, _text, Graphics.FONT_TINY, w / 2, h / 2, textWidth, h - 6);
            return;
        }
        var titleFont = Graphics.FONT_TINY;
        var valueFont = Graphics.FONT_XTINY;
        var title = Graphics.fitTextToArea(_title as String, titleFont, textWidth, 2 * dc.getFontHeight(titleFont), true);
        var value = Graphics.fitTextToArea(_text, valueFont, textWidth, 2 * dc.getFontHeight(valueFont), true);
        if (title == null) { title = ""; }
        if (value == null) { value = ""; }
        var titleH = dc.getTextDimensions(title, titleFont)[1];
        var valueH = dc.getTextDimensions(value, valueFont)[1];
        var y = (h - titleH - valueH - 4) / 2;
        dc.drawText(w / 2, y, titleFont, title, Graphics.TEXT_JUSTIFY_CENTER);
        if (!isFocused()) { dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT); }
        else { dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT); }
        dc.drawText(w / 2, y + titleH + 4, valueFont, value, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawWrapped(dc as Graphics.Dc, text as String, font as Graphics.FontType, x as Number, y as Number,
            width as Number, height as Number) as Void {
        var fitted = Graphics.fitTextToArea(text, font, width, height, true);
        dc.drawText(x, y, font, (fitted == null) ? "" : fitted, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

// Menu title, wrapped over up to two lines.
class SettingsMenuTitle extends WatchUi.Drawable {
    private var _text as String;

    function initialize(text as String) {
        Drawable.initialize({});
        _text = text;
    }

    function draw(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var font = Graphics.FONT_XTINY;
        var fitted = Graphics.fitTextToArea(_text, font, w * 6 / 10, dc.getHeight(), true);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, dc.getHeight() / 2, font, (fitted == null) ? "" : fitted,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
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

    // Current value of a SettingsMenuData item as text, e.g. "On" or "Stress".
    function valueLabel(entry as Array) as String {
        var value = Application.Properties.getValue(entry[0] as String);
        if (entry[2] == null) {
            return (value == true) ? "On" : "Off";
        }
        var options = WatchUi.loadResource(entry[2] as ResourceId) as Array<Array>;
        return labelFor(options, value as Number?);
    }
}
