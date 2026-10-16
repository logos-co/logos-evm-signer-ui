#pragma once

#include <string>
#include <vector>

// What this signer adds to the sheet from what it already holds. Plain C++ with no Qt and no
// host, so tests/ builds and runs it with any compiler.
namespace sheet {

// Section 3 for a Bitcoin request, added up from section 2's own lines. Empty for anything that
// is not one, so the EVM reading is untouched.
std::vector<std::string> bitcoinReading(const std::vector<std::string> &lines);

} // namespace sheet
