// SPDX-License-Identifier: GPL-3.0-or-later
// Custom (Laurance): one consistent "open dropdown" header for every tool that
// opens inside the Utilities section (Cleaner, Clipboard, Uninstaller, ...).

import SwiftUI

private struct PanelToolHeaderHiddenKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while a tool is shown under the shared dropdown header, so the
    /// tool's own header (title plus its own X or arrow) is left out.
    var panelToolHeaderHidden: Bool {
        get { self[PanelToolHeaderHiddenKey.self] }
        set { self[PanelToolHeaderHiddenKey.self] = newValue }
    }
}
