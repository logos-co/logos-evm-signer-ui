#include "sheet_lines.h"

#include <cstdint>
#include <regex>
#include <set>

namespace sheet {

namespace {

bool asciiLetter(char c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
bool asciiDigit(char c) { return c >= '0' && c <= '9'; }
bool startsWith(const std::string &s, const std::string &p) { return s.compare(0, p.size(), p) == 0; }

// Short and plain, so a name cannot carry a second id in brackets, a look-alike letter or a
// direction mark: ASCII letters first, then letters, digits, single spaces and - . ' only.
bool plainName(const std::string &s)
{
    if (s.empty() || s.size() > 40 || !asciiLetter(s.front()) || s.back() == ' ') {
        return false;
    }
    for (size_t i = 0; i < s.size(); ++i) {
        const char c = s[i];
        if (!(asciiLetter(c) || asciiDigit(c) || c == '-' || c == '.' || c == '\''
              || (c == ' ' && s[i - 1] != ' '))) {
            return false;
        }
    }
    return true;
}

// What two names have to differ in to be told apart at a glance: letters and digits, any case.
std::string folded(const std::string &s)
{
    std::string out;
    for (const char c : s) {
        if (asciiDigit(c) || (c >= 'a' && c <= 'z')) {
            out += c;
        } else if (c >= 'A' && c <= 'Z') {
            out += char(c - 'A' + 'a');
        }
    }
    return out;
}

constexpr uint64_t kCoin = 100000000;
constexpr uint64_t kMaxSats = 21000000 * kCoin;

// As the manager prints an amount: whole coins, a point, eight digits.
bool amount(const std::string &whole, const std::string &frac, uint64_t &sats)
{
    if (whole.size() > 8) {
        return false;
    }
    sats = std::stoull(whole) * kCoin + std::stoull(frac);
    return sats <= kMaxSats;
}

std::string btc(uint64_t sats)
{
    const std::string frac = std::to_string(sats % kCoin);
    return std::to_string(sats / kCoin) + "." + std::string(8 - frac.size(), '0') + frac + " BTC";
}

} // namespace

std::string installedName(const std::string &module,
                          const std::vector<std::pair<std::string, std::string>> &installed)
{
    std::set<std::string> names;
    for (const auto &[name, displayName] : installed) {
        if (name == module && !displayName.empty()) {
            names.insert(displayName);
        }
    }
    // Two copies that disagree give neither name.
    if (names.size() != 1) {
        return {};
    }
    const std::string name = *names.begin();
    if (!plainName(name) || name == module) {
        return {};
    }
    for (const auto &[other, displayName] : installed) {
        if (other != module && folded(displayName) == folded(name)) {
            return {};
        }
    }
    return name;
}

std::vector<std::string> bitcoinReading(const std::vector<std::string> &lines)
{
    // The manager's Bitcoin layout: the wallet, the commitment, one item, then the PSBT's lines.
    if (lines.size() < 4 || !startsWith(lines[0], "Wallet: ") || !startsWith(lines[1], "Commitment: ")
        || lines[2] != "1 item(s) to sign:" || !startsWith(lines[3], "  [1] Bitcoin ")) {
        return {};
    }
    // Anything not read below, or figures that do not balance: section 2 stands alone.
    const std::vector<std::string> whole{
        "Interpreted: nothing to add — section 2 is the signer manager's whole reading of this "
        "Bitcoin transaction."};

    static const std::string amt = "([0-9]+)\\.([0-9]{8}) BTC";
    static const std::regex own("(?:Change|Receive) " + amt
                                + " back to this wallet \\(m/[^()]*, checked\\)");
    static const std::regex script("Send " + amt + " to a script with no address: ([0-9a-f]+)");
    static const std::regex send("Send " + amt + " to ([A-Za-z0-9]+)");
    static const std::regex fee("Fee ([0-9]{1,3}(?:,[0-9]{3})*) sats, about [0-9]+\\.[0-9] sat/vB, "
                                "computed from the inputs");
    static const std::regex spends("Spends [0-9]+ coins? worth " + amt
                                   + "(?: · replaceable \\(RBF\\))?");

    uint64_t back = 0, out = 0, paid = 0, in = 0;
    int outputs = 0;
    std::set<std::string> to;
    std::string feeText;
    enum { Outputs, Spends, Done } at = Outputs;
    for (size_t i = 4; i < lines.size(); ++i) {
        if (!startsWith(lines[i], "      ")) {
            return whole;
        }
        const std::string l = lines[i].substr(6);
        std::smatch m;
        uint64_t v = 0;
        if (at == Outputs && std::regex_match(l, m, own) && amount(m[1].str(), m[2].str(), v)) {
            back += v;
            ++outputs;
        } else if (at == Outputs && (std::regex_match(l, m, script) || std::regex_match(l, m, send))
                   && amount(m[1].str(), m[2].str(), v)) {
            out += v;
            to.insert(m[3].str());
            ++outputs;
        } else if (at == Outputs && outputs > 0 && std::regex_match(l, m, fee)) {
            feeText = m[1].str();
            std::string digits;
            for (const char c : feeText) {
                if (c != ',') {
                    digits += c;
                }
            }
            if (digits.size() > 16) {
                return whole;
            }
            paid = std::stoull(digits);
            at = Spends;
        } else if (at == Spends && std::regex_match(l, m, spends) && amount(m[1].str(), m[2].str(), in)) {
            at = Done;
        } else {
            return whole;
        }
        if (back > kMaxSats || out > kMaxSats || paid > kMaxSats) {
            return whole;
        }
    }
    if (at != Done || back + out + paid != in) {
        return whole;
    }

    std::vector<std::string> r{"Interpreted: Bitcoin — section 2's own figures, added up on this device"};
    if (out == 0) {
        r.push_back(paid == 0 ? "  Everything comes back to this wallet, and there is no fee."
                              : "  Everything comes back to this wallet; you pay only the " + feeText
                                    + "-sat fee.");
        return r;
    }
    const std::string where = to.size() == 1 ? "an address" : std::to_string(to.size()) + " addresses";
    r.push_back("  Sends " + btc(out) + " to " + where + " not shown to be this wallet's; "
                + (back == 0 ? std::string("nothing comes back") : btc(back) + " comes back to this wallet")
                + "; " + (paid == 0 ? std::string("no fee") : "fee " + feeText + (paid == 1 ? " sat" : " sats"))
                + ".");
    return r;
}


void ErrorHold::pollFailed(std::string text) { m_poll = std::move(text); }

void ErrorHold::signerRefused(std::string text, std::string chosen, const std::string &presence)
{
    m_refused = std::move(text);
    m_refusedSigner = std::move(chosen);
    m_refusedAbsent = presence.empty() || presence == "absent";
}

bool ErrorHold::pollRead(const std::string &shown)
{
    const bool own = !m_poll.empty() && shown == m_poll;
    m_poll.clear();
    return own;
}

bool ErrorHold::signersRead(const std::string &shown, const std::string &chosen, const std::string &presence)
{
    if (m_refused.empty() || shown != m_refused) {
        m_refused.clear();
        return false;
    }
    const bool back = m_refusedAbsent && !presence.empty() && presence != "absent";
    if (chosen == m_refusedSigner && !back) {
        return false;
    }
    m_refused.clear();
    return true;
}

} // namespace sheet
