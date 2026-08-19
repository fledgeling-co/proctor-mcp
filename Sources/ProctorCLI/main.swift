import Foundation
import ProctorCore

// PRO-0073. `proctor` — the operator CLI.
//
// `proctor-shim` stays as its own binary and its own alias, so every existing
// host configuration keeps working untouched.
exit(CLI.run(Array(CommandLine.arguments.dropFirst())).rawValue)
