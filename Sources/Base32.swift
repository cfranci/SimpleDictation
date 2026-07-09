// Sources/Base32.swift
//
// Crockford Base32 codec for SimpleDictation license tokens.
//
// This MUST stay byte-identical to scripts/gen-keys.mjs (base32Encode/base32Decode)
// and to the Worker's base32 helpers. Same alphabet, same I/L->1 and O->0 folding,
// same U-rejection, same dash/space stripping. If these drift, tokens silently
// fail to verify (isValidSignature returns false with no obvious cause).
//
// Used by LicenseManager.verify(): the token is SD1-<base32(payload)>.<base32(sig)>;
// we decode BOTH segments to their exact raw bytes and verify the Ed25519
// signature over those exact payload bytes (never re-encode the JSON).

import Foundation

enum Base32 {
    // Crockford alphabet — excludes I, L, O, U. MUST match gen-keys.mjs + the Worker.
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    private static let decodeMap: [Character: UInt8] = {
        var m = [Character: UInt8]()
        for (i, c) in alphabet.enumerated() { m[c] = UInt8(i) }
        return m
    }()

    static func encode(_ data: Data) -> String {
        var bits = 0, value = 0
        var out = ""
        for byte in data {
            value = (value << 8) | Int(byte)
            bits += 8
            while bits >= 5 { out.append(alphabet[(value >> (bits - 5)) & 31]); bits -= 5 }
        }
        if bits > 0 { out.append(alphabet[(value << (5 - bits)) & 31]) }
        return out
    }

    /// Decode Crockford base32 to raw bytes. Forgives good-faith typos (I/L -> 1,
    /// O -> 0), strips dashes/spaces/other non-alphanumerics, case-insensitive.
    /// Returns nil on any character not in the alphabet after folding — notably
    /// U is rejected (Crockford treats U as invalid; remapping it would silently
    /// mis-decode a token into a wrong-but-accepted byte string).
    static func decode(_ string: String) -> Data? {
        let folded = string.uppercased()
            .replacingOccurrences(of: "I", with: "1")
            .replacingOccurrences(of: "L", with: "1")
            .replacingOccurrences(of: "O", with: "0")
        // Strip anything not A-Z0-9 (dashes, spaces, the SD42- prefix, etc.)
        let norm = folded.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(Character.init)

        var bits = 0, value = 0
        var out = [UInt8]()
        for c in norm {
            guard let d = decodeMap[c] else { return nil }   // U (and any stray char) -> reject
            value = (value << 5) | Int(d)
            bits += 5
            if bits >= 8 { out.append(UInt8((value >> (bits - 8)) & 0xff)); bits -= 8 }
        }
        return Data(out)
    }
}
