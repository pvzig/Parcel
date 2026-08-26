/// The shape restrictions enforced by `FormURLEncodedBodyEncoder`.
enum FormURLEncodedShapeError {
  static let nestedKeyedContainer =
    "FormURLEncodedBodyEncoder does not support nested keyed containers."
  static let nestedArray = "Form field arrays cannot contain nested arrays."
  static let nilArrayElement = "Form field arrays cannot contain nil elements."
  static let topLevelKeyedOnly =
    "FormURLEncodedBodyEncoder only supports top-level keyed values."
  static let arrayUnderKeyOnly =
    "FormURLEncodedBodyEncoder only supports arrays nested under a keyed value."
}
