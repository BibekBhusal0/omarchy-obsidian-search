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
  property var manifest: null
  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property var items: []
  property var allItems: []
  property string vaultName: ""
  property string searchScript: root.manifest && root.manifest.__sourceDir
    ? root.manifest.__sourceDir + "/search.sh" : ""

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
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    if (!root.allItems.length) root.runSearch()
    else root.filter()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  function runSearch() {
    root.searchSerial += 1
    searchProc.serial = root.searchSerial
    searchProc.collected = ""
    var args = [root.searchScript]
    var vaultPath = root.pluginSetting("vaultPath")
    if (vaultPath) args.push(vaultPath)
    searchProc.command = args
    searchProc.running = true
  }

  function pluginSetting(name) {
    if (!root.shell || !root.shell.shellConfig) return ""
    var plugins = root.shell.shellConfig.plugins
    if (!Array.isArray(plugins)) return ""
    var manifest = root.manifest
    var id = manifest && manifest.id ? manifest.id : ""
    for (var i = 0; i < plugins.length; i++) {
      if (plugins[i] && plugins[i].id === id) {
        var value = plugins[i][name]
        return value === undefined || value === null ? "" : String(value)
      }
    }
    return ""
  }

  function parseResults(raw) {
    var lines = String(raw || "").split("\n")
    var rows = []
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line) continue
      if (line.indexOf("#vault\t") === 0) {
        if (!root.vaultName) root.vaultName = line.slice("#vault\t".length)
        continue
      }
      var parts = line.split("\t")
      if (parts.length < 4) continue
      var path = parts[2]
      var icon = "󰠮"
      if (parts[1] === "Canvas") icon = "󰇞"
      else if (parts[1] === "Base") icon = ""
      rows.push({
        icon: icon,
        label: parts[0],
        detail: parts[1],
        action: parts[3],
        title: parts[0],
        domain: path,
        link: parts[3]
      })
    }
    return rows
  }

  // Client-side fuzzy ranking on every keystroke; no per-key process spawn.
  function filter() {
    var query = root.filterText.trim()
    var shown = []
    if (!query) {
      shown = root.allItems.slice()
    } else {
      shown = FuzzySearch.search(root.filterText, root.allItems)
      shown.unshift({
        icon: "󱘒",
        label: "Create new note - " + query,
        detail: "Create '" + query + ".md' in " + root.vaultName,
        action: "obsidian \"obsidian://new?vault=" + encodeURIComponent(root.vaultName) + "&name=" + encodeURIComponent(query) + "\"",
        title: query,
        domain: root.vaultName,
        link: ""
      })
    }
    root.items = shown
    root.rebuildDisplay()
  }

  function rebuildDisplay() {
    displayModel.clear()
    for (var j = 0; j < root.items.length; j++) displayModel.append(root.items[j])

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function select(delta) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    resultList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.filter()
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  function activateIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    var action = row.action
    root.opened = false
    Util.execDetached(action)
  }

  ListModel { id: displayModel }

  Process {
    id: searchProc
    property string collected: ""
    property int serial: 0
    stdout: SplitParser {
      onRead: function(data) { searchProc.collected += data + "\n" }
    }
    onExited: {
      if (searchProc.serial !== root.searchSerial) return
      root.allItems = root.parseResults(searchProc.collected)
      root.filter()
    }
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
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

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.close()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-6)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(6)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Right) {
            if (root.cursorActive) root.activateIndex(root.selectedIndex)
            else if (displayModel.count > 0) root.cursorActive = true
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
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
                  onPositionChanged: function(mouse) {
                    root.selectFromPointer(row.index, row, mouse)
                  }
                  onClicked: {
                    root.cursorActive = true
                    root.selectedIndex = row.index
                    root.activateIndex(row.index)
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
