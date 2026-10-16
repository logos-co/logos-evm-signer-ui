#pragma once

#include <string>
#include <utility>
#include <vector>

// What this signer works out for the sheet. Plain C++ with no Qt and no host, so tests/ builds
// and runs it with any compiler.
namespace sheet {

// The name the user's installed package gives `module`, or "" when there is none to trust: no
// name, one that is not short plain ASCII, or one another installed package wears too.
// `installed` is every installed package as (name, displayName).
std::string installedName(const std::string &module,
                          const std::vector<std::pair<std::string, std::string>> &installed);

// Section 3 for a Bitcoin request, added up from section 2's own lines. Empty for anything that
// is not one, so the EVM reading is untouched.
std::vector<std::string> bitcoinReading(const std::vector<std::string> &lines);

} // namespace sheet
