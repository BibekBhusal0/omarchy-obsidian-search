import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "FuzzySearch.js" as FuzzySearch

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property var items: []
  property var allItems: []
  property string vaultName: ""
  property string vaultPathResolved: ""
  property bool dailyEnabled: false
  property bool configReady: false
  property var pendingLaunch: []
  property bool hasPendingLaunch: false
  readonly property string searchScript: Qt.resolvedUrl("search.sh").toString().replace(/^file:\/\//, "")

  // Shares the [menu] surface tokens so themes style it like the menu.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  property int cardWidth: Math.min(Style.space(520), panel.width - Style.gapsOut * 2)
  property int rowHeight: Math.max(Style.space(44), Style.font.body + Style.spacing.rowPaddingX * 2)
  property int cardHeight: Math.min(contentMargin * 2 + headerHeight + contentSpacing + rowHeight * Math.min(root.items.length, 9) + Style.space(8), panel.height - Style.gapsOut * 2)
  property int searchSerial: 0

  function open(payloadJson) {
    root.opened = true;
    root.filterText = "";
    root.selectedIndex = 0;
    root.cursorActive = true;
    root.disarmPointer();
    root.filter();
    root.runSearch();
    Qt.callLater(function () {
        keyCatcher.forceActiveFocus();
      });
  }

  function close() {
    root.opened = false;
  }

  function toggle() {
    if (root.opened)
      root.close();
    else
      root.open("{}");
  }

  function runSearch() {
    root.searchSerial += 1;
    searchProc.serial = root.searchSerial;
    searchProc.collected = "";
    root.dailyEnabled = false;
    root.vaultName = "";
    root.vaultPathResolved = "";
    var args = [root.searchScript];
    var vaultPath = root.cfg("vaultPath", "");
    if (vaultPath)
      args.push(vaultPath);
    args.push("--show-daily=" + (root.cfgBool("showDailyNotes", true) ? "1" : "0"));
    args.push("--show-templates=" + (root.cfgBool("showTemplates", false) ? "1" : "0"));
    searchProc.command = args;
    searchProc.running = true;
  }

  property var fileConfig: ({})
  function parseFileConfig(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""));
      return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : ({});
    } catch (e) {
      return ({});
    }
  }
  function cfg(name, fallback) {
    var value = root.fileConfig ? root.fileConfig[name] : undefined;
    return value === undefined || value === null ? fallback : value;
  }
  function cfgBool(name, fallback) {
    var raw = root.cfg(name, "");
    if (raw === "")
      return fallback;
    if (raw === true)
      return true;
    if (raw === false)
      return false;
    var lowered = String(raw).toLowerCase();
    if (lowered === "true" || lowered === "1" || lowered === "yes")
      return true;
    if (lowered === "false" || lowered === "0" || lowered === "no")
      return false;
    return fallback;
  }
  FileView {
    id: configFile
    path: Quickshell.env("HOME") + "/.config/omarchy/obsidian-search.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.fileConfig = root.parseFileConfig(text());
      root.configReady = true;
      root.onConfigChanged();
    }
    onFileChanged: configFile.reload()
    onLoadFailed: {
      root.fileConfig = ({});
      root.configReady = true;
      root.onConfigChanged();
    }
  }

  // Re-lists with the new showDailyNotes/showTemplates flags once the config
  // arrives or changes, and prewarms the cache at shell startup so the first
  // open is instant. Cached rows stay visible until the fresh list lands.
  function onConfigChanged() {
    root.filter();
    root.runSearch();
  }

  function parseResults(raw) {
    var lines = String(raw || "").split("\n");
    var rows = [];
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim();
      if (!line)
        continue;
      if (line.indexOf("#vault\t") === 0) {
        root.vaultName = line.slice("#vault\t".length);
        continue;
      }
      if (line.indexOf("#vaultpath\t") === 0) {
        root.vaultPathResolved = line.slice("#vaultpath\t".length).trim();
        continue;
      }
      if (line === "#daily" || line.indexOf("#daily\t") === 0) {
        root.dailyEnabled = true;
        continue;
      }
      var parts = line.split("\t");
      if (parts.length < 4)
        continue;
      var uri = parts[parts.length - 1];
      if (uri.indexOf("obsidian://") !== 0)
        continue;
      var path = parts[2];
      var kind = parts[1];
      var icon = "󰠮";
      if (kind === "Canvas")
        icon = "󰇞";
      else if (kind === "Base")
        icon = "";
      else if (kind === "Daily Note")
        icon = "";
      else if (kind === "Template")
        icon = "󱘒";
      rows.push({
          "icon": icon,
          "label": parts[0],
          "detail": kind,
          "action": uri,
          "title": parts[0],
          "domain": path,
          "link": uri,
          "kind": kind,
          "rel": path
        });
    }
    return rows;
  }

  // Client-side fuzzy ranking on every keystroke; no per-key process spawn.
  // With an empty query the first row pins today's daily note (open or
  // create); any other query keeps the previous behavior plus a create row.
  function filter() {
    var query = root.filterText.trim();
    var wantDaily = root.cfgBool("showDailyNotes", true);
    var wantTemplates = root.cfgBool("showTemplates", false);
    var shown = [];
    if (!query) {
      shown = root.allItems.slice();
      if (root.dailyEnabled)
        shown.unshift(root.dailyRow());
    } else {
      shown = FuzzySearch.search(root.filterText, root.allItems);
      if (root.matchesDaily(query))
        shown.unshift(root.dailyRow());
      shown.push({
          "icon": "󱘒",
          "label": "Create new note - " + query,
          "detail": "Create '" + query + ".md' in " + root.vaultName,
          "action": "obsidian://new?vault=" + encodeURIComponent(root.vaultName) + "&name=" + encodeURIComponent(query),
          "title": query,
          "domain": root.vaultName,
          "link": "",
          "kind": "New Note",
          "rel": query + ".md"
        });
    }
    shown = shown.filter(function (row) {
        if (row.kind === "Daily Note")
          return wantDaily;
        if (row.kind === "Template")
          return wantTemplates;
        return true;
      });
    root.items = shown;
    root.rebuildDisplay();
  }

  function matchesDaily(query) {
    if (!root.dailyEnabled)
      return false;
    var q = query.trim().toLowerCase();
    return q.indexOf("daily") !== -1 || q.indexOf("today") !== -1;
  }

  function dailyRow() {
    return {
      "icon": "",
      "label": "Today's daily note",
      "detail": "Open in " + root.vaultName,
      "action": "obsidian://daily?vault=" + encodeURIComponent(root.vaultName),
      "title": "Today's daily note",
      "domain": root.vaultName,
      "link": "",
      "kind": "Daily Pin",
      "rel": ""
    };
  }

  function rebuildDisplay() {
    displayModel.clear();
    for (var j = 0; j < root.items.length; j++)
      displayModel.append(root.items[j]);
    if (displayModel.count === 0)
      selectedIndex = 0;
    else if (selectedIndex >= displayModel.count)
      selectedIndex = displayModel.count - 1;
    else if (selectedIndex < 0)
      selectedIndex = 0;
    Qt.callLater(function () {
        if (displayModel.count > 0)
          resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
      });
  }

  function select(delta) {
    if (displayModel.count === 0)
      return;
    root.disarmPointer();
    if (!cursorActive) {
      cursorActive = true;
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0;
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count;
    }
    resultList.positionViewAtIndex(selectedIndex, ListView.Contain);
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter;
    root.selectedIndex = 0;
    root.cursorActive = true;
    root.disarmPointer();
    root.filter();
  }

  function disarmPointer() {
    pointerGate.reset();
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse))
      return;
    root.cursorActive = true;
    root.selectedIndex = index;
  }

  function absPathFor(rel) {
    if (!rel)
      return "";
    if (rel.charAt(0) === "/")
      return rel;
    var base = root.vaultPathResolved;
    if (!base) {
      base = root.cfg("vaultPath", "");
      if (base.indexOf("~/") === 0)
        base = Quickshell.env("HOME") + base.slice(1);
    }
    if (!base)
      return "";
    return base.replace(/\/$/, "") + "/" + rel;
  }

  function launchArgvFor(mode, row) {
    if (mode === "obsidian")
      return ["obsidian", row.action];
    var kind = row.kind || "Note";
    var forcedObsidian = kind === "Canvas" || kind === "Base" || kind === "Daily Note" || kind === "Daily Pin" || kind === "Template";
    var opener = mode === "omawrite" ? "omawrite" : mode === "neovim" ? "nvim" : root.cfg("opener", "") || "obsidian";
    var lowered = String(opener).toLowerCase();
    if (!forcedObsidian) {
      if (lowered === "omawrite")
        return ["omawrite", root.absPathFor(row.rel)];
      if (lowered === "neovim" || lowered === "nvim" || lowered === "vim")
        return ["omarchy", "launch", "tui", "--app-id=nvim-obsidian", "nvim", root.absPathFor(row.rel)];
      if (lowered !== "obsidian")
        return [String(opener), root.absPathFor(row.rel)];
    }
    return ["obsidian", row.action];
  }

  function activateIndex(index, mode) {
    if (index < 0 || index >= displayModel.count)
      return;
    var row = displayModel.get(index);
    var kind = row.kind || "Note";
    var argv = root.launchArgvFor(mode || "", row);
    var needsFile = kind === "New Note" && argv[0] !== "obsidian";
    root.opened = false;
    if (needsFile) {
      var abs = root.absPathFor(row.rel);
      if (!abs)
        return;
      root.pendingLaunch = argv;
      root.hasPendingLaunch = true;
      var dir = abs.slice(0, abs.lastIndexOf("/"));
      ensureProc.command = ["bash", "-lc", 'mkdir -p "$1" && [ -e "$2" ] || touch "$2"', "bash", dir, abs];
      ensureProc.running = true;
      return;
    }
    Util.execArgv(argv);
  }

  ListModel {
    id: displayModel
  }

  Process {
    id: searchProc
    property string collected: ""
    property int serial: 0
    stdout: SplitParser {
      onRead: function (data) {
        searchProc.collected += data + "\n";
      }
    }
    onExited: {
      if (searchProc.serial !== root.searchSerial)
        return;
      root.allItems = root.parseResults(searchProc.collected);
      root.filter();
    }
  }

  // Creates the parent dir plus an empty file for daily pins and new notes
  // opened in an external editor, then runs the pending launch.
  Process {
    id: ensureProc
    onExited: {
      if (!root.hasPendingLaunch)
        return;
      root.hasPendingLaunch = false;
      launchProc.command = root.pendingLaunch;
      launchProc.running = true;
    }
  }

  Process {
    id: launchProc
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }
    color: "transparent"
    WlrLayershell.namespace: "obsidian-search"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: Math.min(root.cardHeight, panel.height - Style.gapsOut * 2)
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea {
        anchors.fill: parent
        onClicked: {
        }
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function (event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText)
              root.setFilter("");
            else
              root.close();
            event.accepted = true;
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText));
            event.accepted = true;
          } else if (event.key === Qt.Key_Up) {
            root.select(-1);
            event.accepted = true;
          } else if (event.key === Qt.Key_Down) {
            root.select(1);
            event.accepted = true;
          } else if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_K || event.key === Qt.Key_P)) {
            root.select(-1);
            event.accepted = true;
          } else if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_J || event.key === Qt.Key_N)) {
            root.select(1);
            event.accepted = true;
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-6);
            event.accepted = true;
          } else if (event.key === Qt.Key_PageDown) {
            root.select(6);
            event.accepted = true;
          } else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_O) {
            if (root.cursorActive)
              root.activateIndex(root.selectedIndex, "obsidian");
            else if (displayModel.count > 0)
              root.cursorActive = true;
            event.accepted = true;
          } else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_W) {
            if (root.cursorActive)
              root.activateIndex(root.selectedIndex, "omawrite");
            else if (displayModel.count > 0)
              root.cursorActive = true;
            event.accepted = true;
          } else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_N) {
            if (root.cursorActive)
              root.activateIndex(root.selectedIndex, "neovim");
            else if (displayModel.count > 0)
              root.cursorActive = true;
            event.accepted = true;
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Right) {
            if (root.cursorActive)
              root.activateIndex(root.selectedIndex);
            else if (displayModel.count > 0)
              root.cursorActive = true;
            event.accepted = true;
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            root.setFilter(root.filterText + event.text);
            event.accepted = true;
          }
        }

        Column {
          anchors.fill: parent
          anchors.topMargin: card.contentTopInset
          anchors.rightMargin: card.contentRightInset
          anchors.bottomMargin: card.contentBottomInset
          anchors.leftMargin: card.contentLeftInset
          spacing: root.contentSpacing

          Rectangle {
            width: parent.width
            height: root.headerHeight
            radius: root.cornerRadius
            color: "transparent"

            Text {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.filterText || "Search notes…"
              color: root.foreground
              opacity: root.filterText ? 1 : 0.58
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              elide: Text.ElideRight
            }
          }

          Item {
            width: parent.width
            height: root.cardHeight - root.contentMargin * 2 - root.headerHeight - root.contentSpacing

            ListView {
              id: resultList
              anchors.fill: parent
              model: displayModel
              clip: true
              spacing: Style.space(4)
              boundsBehavior: Flickable.StopAtBounds

              delegate: BorderSurface {
                id: row
                required property int index
                required property string icon
                required property string label
                required property string detail

                readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex

                width: ListView.view.width
                height: root.rowHeight
                radius: root.cornerRadius
                color: hasCursor ? root.selectedBackground : "transparent"
                borderSpec: hasCursor ? Border.surfaceSpec("menu", "selected-border", root.selectedText, 0) : Border.none()

                Text {
                  text: row.icon
                  color: row.hasCursor ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(14)
                  anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(46)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  Text {
                    width: parent.width
                    text: row.label
                    color: row.hasCursor ? root.selectedText : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.heading
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    text: row.detail
                    visible: row.detail.length > 0
                    color: row.hasCursor ? root.selectedText : root.foreground
                    opacity: 0.5
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onPositionChanged: function (mouse) {
                    root.selectFromPointer(row.index, row, mouse);
                  }
                  onClicked: {
                    root.cursorActive = true;
                    root.selectedIndex = row.index;
                    root.activateIndex(row.index);
                  }
                }
              }
            }

            Column {
              anchors.centerIn: parent
              spacing: Style.space(8)
              visible: displayModel.count === 0 && !searchProc.running

              Text {
                text: "󰠮"
                color: root.selectedText
                opacity: 0.8
                font.family: root.fontFamily
                font.pixelSize: Style.font.displayLarge
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
              }

              Text {
                text: root.filterText ? "No matches for “" + root.filterText + "”" : "No notes found"
                color: root.foreground
                opacity: 0.7
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
              }
            }
          }
        }
      }
    }
  }
}
