.pragma library

// A backend error as a person reads it: a leading machine code such as "WrongSecret: " is dropped
// and the sentence is kept, starting with a capital. Empty in, empty out.
function human(e) {
    var s = String(e || "").trim().replace(/^[A-Z][A-Za-z]+:\s*/, "")
    return s.length > 0 ? s.charAt(0).toUpperCase() + s.slice(1) : ""
}
