import Contacts
import ContactsUI
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ContactPhonePicker") {
      ContactPhonePicker.register(with: registrar)
    }
  }
}

/// `scenario/contact_picker` → `pickPhone`: the system contact picker, where the
/// user taps one phone number of one contact.
///
/// `CNContactPickerViewController` runs out of process and hands back only what
/// was tapped, so the app needs no Contacts permission and never sees the rest
/// of the address book. Contacts without a number are not selectable.
final class ContactPhonePicker: NSObject, FlutterPlugin, CNContactPickerDelegate {
  private var pending: FlutterResult?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "scenario/contact_picker",
      binaryMessenger: registrar.messenger()
    )
    let instance = ContactPhonePicker()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "pickPhone" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard pending == nil else {
      result(FlutterError(code: "busy", message: "A contact pick is already open.", details: nil))
      return
    }
    guard let presenter = Self.topViewController() else {
      result(FlutterError(code: "unavailable", message: "Nothing to present from.", details: nil))
      return
    }
    pending = result
    let picker = CNContactPickerViewController()
    picker.delegate = self
    picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
    picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
    picker.predicateForSelectionOfProperty = NSPredicate(format: "key == 'phoneNumbers'")
    presenter.present(picker, animated: true)
  }

  func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty) {
    guard let result = pending else { return }
    pending = nil
    guard let number = contactProperty.value as? CNPhoneNumber else {
      result(nil)
      return
    }
    let contact = contactProperty.contact
    let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
    let rawLabel = contactProperty.label ?? ""
    let label = rawLabel.isEmpty
      ? ""
      : CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: rawLabel)
    result([
      "name": name,
      "phone": number.stringValue,
      "type": Self.whatsAppType(rawLabel),
      "label": label,
    ])
  }

  func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
    pending?(nil)
    pending = nil
  }

  /// WhatsApp's phone types; "" for anything it has no word for.
  private static func whatsAppType(_ label: String) -> String {
    switch label {
    case CNLabelPhoneNumberMobile: return "CELL"
    case CNLabelPhoneNumberiPhone: return "IPHONE"
    case CNLabelPhoneNumberMain: return "MAIN"
    case CNLabelHome: return "HOME"
    case CNLabelWork: return "WORK"
    default: return ""
    }
  }

  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let windows = scenes.flatMap { $0.windows }
    var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}
