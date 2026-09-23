import Flutter
import UIKit

public class FlutterEmlMsgViewerPlugin: NSObject, FlutterPlugin, UIDocumentInteractionControllerDelegate {
    private var documentInteractionController: UIDocumentInteractionController?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_eml_msg_viewer", binaryMessenger: registrar.messenger())
        let instance = FlutterEmlMsgViewerPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getTempDirectory":
            let paths = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)
            if let cacheDir = paths.first {
                result(cacheDir)
            } else {
                result(NSTemporaryDirectory())
            }
        case "openFile":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Path is required", details: nil))
                return
            }

            let fileUrl = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: fileUrl.path) else {
                result(FlutterError(code: "FILE_NOT_FOUND", message: "File not found at path: \(path)", details: nil))
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    result(false)
                    return
                }

                guard let topController = FlutterEmlMsgViewerPlugin.topViewController() else {
                    result(FlutterError(code: "NO_VIEW_CONTROLLER", message: "No visible view controller to present from", details: nil))
                    return
                }

                let controller = UIDocumentInteractionController(url: fileUrl)
                controller.delegate = self
                controller.name = fileUrl.lastPathComponent
                self.documentInteractionController = controller

                // Quick Look preview for supported types; otherwise fall back to
                // the "Open in…" sheet so the user can pick another app.
                if controller.presentPreview(animated: true) {
                    result(true)
                    return
                }

                let view = topController.view!
                let rect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
                if controller.presentOptionsMenu(from: rect, in: view, animated: true) {
                    result(true)
                } else {
                    self.documentInteractionController = nil
                    result(false)
                }
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    public func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        return FlutterEmlMsgViewerPlugin.topViewController() ?? UIViewController()
    }

    public func documentInteractionControllerDidEndPreview(_ controller: UIDocumentInteractionController) {
        documentInteractionController = nil
    }

    public func documentInteractionControllerDidDismissOptionsMenu(_ controller: UIDocumentInteractionController) {
        documentInteractionController = nil
    }

    /// Finds the top-most presented view controller of the key window. Looks
    /// through connected scenes first, since `UIApplication.keyWindow` is nil
    /// for scene-based apps (the default for newer Flutter templates).
    private static func topViewController() -> UIViewController? {
        var window: UIWindow?
        if #available(iOS 13.0, *) {
            let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let windows = windowScenes
                .sorted { ($0.activationState == .foregroundActive ? 0 : 1) < ($1.activationState == .foregroundActive ? 0 : 1) }
                .flatMap { $0.windows }
            window = windows.first(where: { $0.isKeyWindow }) ?? windows.first
        }
        if window == nil {
            window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) ?? UIApplication.shared.delegate?.window ?? nil
        }

        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
