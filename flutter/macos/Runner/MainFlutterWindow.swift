import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    // Default 1280x800, minimum 720x480 (high-fidelity prototype).
    self.setContentSize(NSSize(width: 1280, height: 800))
    self.contentMinSize = NSSize(width: 720, height: 480)
    self.center()
    self.title = "Matrix Desktop"

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
