// What this signer adds to the sheet, run with no Qt and no host:
//   c++ -std=c++17 -Isrc src/sheet_lines.cpp tests/sheet_lines_test.cpp -o sheet_lines_test
#include "sheet_lines.h"

#include <iostream>
#include <string>
#include <vector>

namespace {

int failures = 0;

void check(const std::string &label, const std::string &got, const std::string &want)
{
    const bool ok = got == want;
    failures += ok ? 0 : 1;
    std::cout << (ok ? "  PASS  " : "  FAIL  ") << label << "   got=" << got
              << (ok ? "" : "  want=" + want) << "\n";
}

std::string joined(const std::vector<std::string> &lines)
{
    std::string out;
    for (const std::string &l : lines) {
        out += (out.empty() ? "" : "\n") + l;
    }
    return out;
}

// Section 2 for one Bitcoin request, as signer_manager_module renders it.
std::vector<std::string> bitcoin(const std::vector<std::string> &legLines)
{
    std::vector<std::string> out{"Wallet: \"Savings\"", "Commitment: 9f86d081", "1 item(s) to sign:",
                                 "  [1] Bitcoin testnet4 · wallet \"Savings\", native segwit, account 0"};
    for (const std::string &l : legLines) {
        out.push_back("      " + l);
    }
    return out;
}

const std::string kHeadline = "Interpreted: Bitcoin — section 2's own figures, added up on this device";
const std::string kWhole = "Interpreted: nothing to add — section 2 is the signer manager's whole "
                           "reading of this Bitcoin transaction.";

} // namespace

int main()
{
    using sheet::bitcoinReading;
    using sheet::installedName;

    std::cout << "\nsection 3 for a Bitcoin request: the figures section 2 shows, added up\n";
    check("a send to this wallet itself",
          joined(bitcoinReading(bitcoin({"Change 0.00363024 BTC back to this wallet (m/84'/1'/0'/1/0, checked)",
                                         "Receive 0.00003000 BTC back to this wallet (m/84'/1'/0'/0/0, checked)",
                                         "Fee 141 sats, about 1.0 sat/vB, computed from the inputs",
                                         "Spends 1 coin worth 0.00366165 BTC · replaceable (RBF)"}))),
          kHeadline + "\n  Everything comes back to this wallet; you pay only the 141-sat fee.");
    check("a payment out, with change",
          joined(bitcoinReading(bitcoin({"Send 0.00003000 BTC to tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx",
                                         "Change 0.00363024 BTC back to this wallet (m/84'/1'/0'/1/0, checked)",
                                         "Fee 141 sats, about 1.0 sat/vB, computed from the inputs",
                                         "Spends 1 coin worth 0.00366165 BTC"}))),
          kHeadline + "\n  Sends 0.00003000 BTC to an address not shown to be this wallet's; "
                      "0.00363024 BTC comes back to this wallet; fee 141 sats.");
    check("two payees, a grouped fee, nothing back",
          joined(bitcoinReading(bitcoin({"Send 0.00100000 BTC to tb1qaaaa",
                                         "Send 0.00048810 BTC to a script with no address: 51",
                                         "Fee 1,190 sats, about 7.3 sat/vB, computed from the inputs",
                                         "Spends 2 coins worth 0.00150000 BTC · replaceable (RBF)"}))),
          kHeadline + "\n  Sends 0.00148810 BTC to 2 addresses not shown to be this wallet's; "
                      "nothing comes back; fee 1,190 sats.");
    check("two payments to one address are one address",
          joined(bitcoinReading(bitcoin({"Send 0.00001000 BTC to tb1qaaaa", "Send 0.00001000 BTC to tb1qaaaa",
                                         "Fee 100 sats, about 1.0 sat/vB, computed from the inputs",
                                         "Spends 1 coin worth 0.00002100 BTC"}))),
          kHeadline + "\n  Sends 0.00002000 BTC to an address not shown to be this wallet's; "
                      "nothing comes back; fee 100 sats.");

    std::cout << "\nanything it cannot read whole, it does not summarise\n";
    check("a line it does not know",
          joined(bitcoinReading(bitcoin({"Data output (OP_RETURN, 6 bytes) carrying 0.00000000 BTC",
                                         "Change 0.00001000 BTC back to this wallet (m/84'/1'/0'/1/0, checked)",
                                         "Fee 100 sats, about 1.0 sat/vB, computed from the inputs",
                                         "Spends 1 coin worth 0.00001100 BTC"}))),
          kWhole);
    check("figures that do not balance",
          joined(bitcoinReading(bitcoin({"Change 0.00001000 BTC back to this wallet (m/84'/1'/0'/1/0, checked)",
                                         "Fee 100 sats, about 1.0 sat/vB, computed from the inputs",
                                         "Spends 1 coin worth 0.00001101 BTC"}))),
          kWhole);
    check("lines out of the manager's order",
          joined(bitcoinReading(bitcoin({"Change 0.00001000 BTC back to this wallet (m/84'/1'/0'/1/0, checked)",
                                         "Spends 1 coin worth 0.00001100 BTC",
                                         "Fee 100 sats, about 1.0 sat/vB, computed from the inputs"}))),
          kWhole);
    check("no fee or inputs line", joined(bitcoinReading(bitcoin({"Send 0.00001000 BTC to tb1qaaaa"}))), kWhole);
    check("a change line the manager did not check",
          joined(bitcoinReading(bitcoin({"Change 0.00001000 BTC back to this wallet (m/84'/1'/0'/1/0)",
                                         "Fee 100 sats, about 1.0 sat/vB, computed from the inputs",
                                         "Spends 1 coin worth 0.00001100 BTC"}))),
          kWhole);

    std::cout << "\nand an EVM request is left to the decoder, untouched\n";
    check("a transaction", joined(bitcoinReading({"Account: 0xf39F…2266", "Commitment: 9f86d081",
                                                  "1 item(s) to sign:", "  [1] Transaction on chain 1",
                                                  "      To: 0xC02a…6Cc2", "      Value: 0"})),
          "");
    check("a message", joined(bitcoinReading({"Account: 0xf39F…2266", "Commitment: 9f86d081",
                                              "1 item(s) to sign:", "  [1] Sign text message",
                                              "      Text: hello"})),
          "");
    check("nothing at all", joined(bitcoinReading({})), "");

    std::cout << "\nsection 1: the name the installed package gives the requester, or none\n";
    const std::vector<std::pair<std::string, std::string>> installed{
        {"bitcoin_wallet_core_module", "Bitcoin Wallet Core"}, {"bitcoin_wallet_ui", "Bitcoin Wallet"},
        {"signer_manager_module", ""}, {"evm_signer_ui", "Signer"}};
    check("an installed package's own name", installedName("bitcoin_wallet_core_module", installed),
          "Bitcoin Wallet Core");
    check("a module nothing installed names", installedName("signer_probe", installed), "");
    check("a package with no name", installedName("signer_manager_module", installed), "");

    auto named = [](const std::string &displayName) {
        return installedName("some_module", {{"some_module", displayName}});
    };
    check("a name carrying a second id", named("Bitcoin Wallet (bitcoin_wallet_core_module)"), "");
    check("a name with a direction mark", named("Bitcoin \xE2\x80\xAE" "Wallet"), "");
    check("a name with a look-alike letter", named("Bitc\xD0\xBE" "in Wallet"), "");
    check("a name over two lines", named("Bitcoin\nWallet"), "");
    check("a name too long to read at a glance", named("A name that goes on and on past forty chars"), "");
    check("a name that is only the id again", named("some_module"), "");
    check("a plain name", named("Bob's Wallet 2.0"), "Bob's Wallet 2.0");

    auto withImpostor = installed;
    withImpostor.push_back({"evil_module", "bitcoin wallet-core."});
    check("a name another package also wears names neither: the original",
          installedName("bitcoin_wallet_core_module", withImpostor), "");
    check("...nor the one copying it", installedName("evil_module", withImpostor), "");
    check("two copies that disagree name neither",
          installedName("some_module", {{"some_module", "Wallet"}, {"some_module", "Wallet Two"}}), "");
    check("two copies that agree keep the name",
          installedName("some_module", {{"some_module", "Wallet"}, {"some_module", "Wallet"}}), "Wallet");

    std::cout << "\n" << (failures ? "RESULT: FAILURES" : "RESULT: ALL PASS") << "\n";
    return failures ? 1 : 0;
}
