//! The requester half of the signer UI's end-to-end proof.
//!
//! Sequence — this module can ASK but can never APPROVE, and that is the
//! property under test:
//!
//!   1. name the keystore's and the manager's roles (ungated)
//!   2. import a known private key            (keystore custodian only)
//!   3. request_approval for a message        (named modules only)
//!   4. poll approval_status until it settles (Tier B, receipt-gated)
//!   5. fetch_result, print the signature     (Tier B, receipt-gated)
//!
//! Then the same again inside an unlock, two Bitcoin sends (`bitcoin_rounds`), a signature
//! from a device (`device_round`), and one from that device's account once the keystore holds it
//! too, with the person choosing the device (`chosen_round`).
//!
//! Nothing here can reach `approve()`. The signature this prints exists only
//! because a human typed the vault password into the signer UI.
//!
//! The work runs on its own thread rather than in `on_context_ready`, so the
//! first outbound call cannot re-enter the host while this module is still
//! initialising. Outbound calls are marshalled by the SDK, so calling from a
//! worker thread is supported.

use serde_json::{json, Value};
use std::str::FromStr;
use std::time::Duration;

/// Fully qualified rather than imported: the generated scaffold is `include!`d
/// into this module and brings its own `Arc`/`Mutex` into scope.
type Shared = std::sync::Arc<std::sync::Mutex<Value>>;

/// Foundry's well-known account 0. A published test key: never fund it.
const TEST_KEY: &str = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
const VAULT_PASSWORD: &str = "doctest-pw";
/// The mock device's phrase, the BIP-39 test vector: the keystore takes it for the chosen round.
const DEVICE_PHRASE: &str =
    "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
const MESSAGE: &str = "I authorise the doc-test transfer";
/// Foundry's test phrase, imported as a regtest Bitcoin wallet for the Bitcoin rounds.
const PHRASE: &str = "test test test test test test test test test test test junk";
const BTC_PASSWORD: &str = "btc-pw";

/// Who holds the keystore's roles here. Each is a LIST; a bare string is the common
/// single-holder spelling `configure` normalises up. The custodian is this fixture:
/// `evm_keystore_ui` is not in this tree, and a role naming a module that is not there
/// admits nobody, so the key import below would be refused. Only the manager may ask
/// the keystore to sign.
const KEYSTORE_ROLES: &str = r#"{"custodians":"signer_probe","managers":"signer_manager_module"}"#;
/// The manager's: the approver stays `evm_signer_ui`, the surface under test. This fixture is also
/// its custodian, playing the keys app for the unlock in the second round. Its signers are the
/// keystore and a mock device.
const MANAGER_ROLES: &str = r#"{"approvers":"evm_signer_ui","custodians":["evm_keystore_ui","signer_probe"],"signers":["keystore_module","mock_device_signer"]}"#;

/// Printed on stdout so the doc-test can assert on the app log without needing
/// a CLI — Basecamp has none.
const MARK: &str = "SIGNER_PROBE";

/// What a requester tells the user when an offer expires unacknowledged. The
/// manager's `expired_no_ack` is a protocol fact; this is the human sentence
/// it means. Signing requires the Signer to be open — that is the design, not
/// a limitation to apologise for — so the guidance is simply to open it.
const NEEDS_APPROVER_MESSAGE: &str =
    "No signer is listening. Open the Signer app to approve this request.";

pub trait SignerProbeModule: Send + 'static {
    /// What the probe has got so far — `{ ok, state, address?, handle?, signed? }`.
    /// Ungated on purpose: it is a fixture, and it holds no secret worth gating.
    fn status(&mut self) -> String;
    fn on_context_ready(&mut self, _ctx: &RustModuleContext) {}
}

include!(concat!(env!("CARGO_MANIFEST_DIR"), "/generated/provider_gen.rs"));

#[derive(Default)]
struct SignerProbeModuleImpl {
    state: Shared,
}

fn ok_value(reply: Result<String, impl std::fmt::Debug>) -> Result<Value, String> {
    let raw = reply.map_err(|e| format!("{e:?}"))?;
    let v: Value = serde_json::from_str(&raw).map_err(|e| e.to_string())?;
    if v.get("ok").and_then(Value::as_bool) == Some(true) {
        Ok(v)
    } else {
        Err(v
            .get("error")
            .and_then(Value::as_str)
            .unwrap_or("call failed")
            .to_string())
    }
}

/// Ask, wait until the person decides, and collect what was signed. `marker` names the request
/// in the log.
fn ask_and_collect(intent: &Value, marker: &str) -> Result<Value, String> {
    let v = ok_value(modules().signer_manager_module.request_approval(&intent.to_string()))?;
    let field = |k: &str| v.get(k).and_then(Value::as_str).unwrap_or_default().to_string();
    let (handle, receipt) = (field("handle"), field("receipt"));
    println!("{MARK}_{marker}: {handle}");
    for _ in 0..600 {
        std::thread::sleep(Duration::from_millis(250));
        let Ok(v) = ok_value(modules().signer_manager_module.approval_status(&handle, &receipt)) else { continue };
        if matches!(v.get("state").and_then(Value::as_str), Some("offered" | "rendered" | "signing")) {
            continue;
        }
        let reason = v.get("reason").and_then(Value::as_str).unwrap_or("").to_string();
        if reason != "approved" {
            return Err(reason);
        }
        let f = ok_value(modules().signer_manager_module.fetch_result(&handle, &receipt))?;
        let _ = modules().signer_manager_module.ack_result(&handle, &receipt);
        return Ok(f.get("signed").cloned().unwrap_or(Value::Null));
    }
    Err(format!("nobody decided {marker}"))
}

/// The second round: the account unlocked for this module, each signature confirmed, so the
/// signer approves with no password. Signs once and collects the signature.
fn unlocked_round(address: &str) -> Result<String, String> {
    // After the doc-test has seen the queue empty: a request arriving at once replaces that line.
    std::thread::sleep(Duration::from_secs(8));
    let terms = json!({ "account": address, "password": VAULT_PASSWORD, "count": 1,
                        "apps": ["signer_probe"], "confirm": true });
    ok_value(modules().signer_manager_module.unlock(&terms.to_string()))?;
    // No form of the word the doc-test clicks by text, as in the first round.
    let intent = json!({ "address": address, "purpose": "Doc-test: sign again, unlocked",
                         "legs": [{ "kind": "message", "text": "Unlocked for one signature" }] });
    let signed = ask_and_collect(&intent, "REQUESTED_UNLOCKED")?;
    Ok(signed.get(0).and_then(Value::as_str).unwrap_or("").to_string())
}

/// A PSBT spending the wallet's first receive coin to a stranger, change to its first change key.
/// The funding is made up and nothing is broadcast.
fn psbt_for(xpub: &str, fingerprint: &str) -> Result<String, String> {
    use bitcoin::bip32::{ChildNumber, DerivationPath, Fingerprint, Xpub};
    use bitcoin::{absolute::LockTime, transaction::Version};
    use bitcoin::{Address, Amount, CompressedPublicKey, Network, OutPoint, Psbt, ScriptBuf, Sequence};
    use bitcoin::{Transaction, TxIn, TxOut, Txid, Witness};
    let e = |e: &dyn std::fmt::Display| e.to_string();
    let secp = bitcoin::secp256k1::Secp256k1::verification_only();
    let account = Xpub::from_str(xpub).map_err(|x| e(&x))?;
    let fp = Fingerprint::from_str(fingerprint).map_err(|x| e(&x))?;
    let key = |change: u32| -> Result<CompressedPublicKey, String> {
        let path = [ChildNumber::Normal { index: change }, ChildNumber::Normal { index: 0 }];
        Ok(CompressedPublicKey(account.derive_pub(&secp, &path).map_err(|x| e(&x))?.public_key))
    };
    let (receive, change) = (key(0)?, key(1)?);
    let input = |txid: Txid, sequence: Sequence| TxIn {
        previous_output: OutPoint { txid, vout: 0 },
        script_sig: ScriptBuf::new(),
        sequence,
        witness: Witness::new(),
    };
    let funding = Transaction {
        version: Version::TWO,
        lock_time: LockTime::ZERO,
        input: vec![input(Txid::from_str(&"11".repeat(32)).map_err(|x| e(&x))?, Sequence::MAX)],
        output: vec![TxOut { value: Amount::from_sat(100_000), script_pubkey: ScriptBuf::new_p2wpkh(&receive.wpubkey_hash()) }],
    };
    // Not this wallet's: the key of secret 1, the generator point.
    let theirs = CompressedPublicKey::from_str("0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798")
        .map_err(|x| e(&x))?;
    let spend = Transaction {
        version: Version::TWO,
        lock_time: LockTime::ZERO,
        input: vec![input(funding.compute_txid(), Sequence::ENABLE_RBF_NO_LOCKTIME)],
        output: vec![
            TxOut { value: Amount::from_sat(60_000), script_pubkey: Address::p2wpkh(&theirs, Network::Regtest).script_pubkey() },
            TxOut { value: Amount::from_sat(39_000), script_pubkey: ScriptBuf::new_p2wpkh(&change.wpubkey_hash()) },
        ],
    };
    let mut psbt = Psbt::from_unsigned_tx(spend).map_err(|x| e(&x))?;
    let path = |c: u32| DerivationPath::from_str(&format!("m/84'/1'/0'/{c}/0")).map_err(|x| e(&x));
    psbt.inputs[0].witness_utxo = Some(funding.output[0].clone());
    psbt.inputs[0].non_witness_utxo = Some(funding);
    psbt.inputs[0].bip32_derivation.insert(receive.0, (fp, path(0)?));
    psbt.outputs[1].bip32_derivation.insert(change.0, (fp, path(1)?));
    Ok(psbt.to_string())
}

/// How many signatures a signed PSBT carries, or `None` for anything else.
fn psbt_signatures(item: &Value) -> Option<usize> {
    let psbt = bitcoin::Psbt::from_str(item.as_str()?).ok()?;
    Some(psbt.inputs.iter().map(|i| i.partial_sigs.len() + usize::from(i.tap_key_sig.is_some())).sum())
}

/// The Bitcoin rounds: the test phrase as a regtest wallet, then one send approved with the
/// wallet's password and one inside a confirmed unlock. Prints each PSBT's signature count.
fn bitcoin_rounds() -> Result<(), String> {
    std::thread::sleep(Duration::from_secs(8));
    let p = json!({ "phrase": PHRASE, "family": "bitcoin", "chain": "test", "password": BTC_PASSWORD,
                    "label": "Regtest wallet" });
    let v = ok_value(modules().keystore_module.import_bitcoin(&p.to_string()))?;
    let text = |k: &str| v.get(k).and_then(Value::as_str).unwrap_or_default().to_string();
    // The account xpub, read off the receive descriptor: wpkh([fp/84'/1'/0']tpub…/0/*)#sum.
    let external = text("external");
    let xpub = external.split(']').nth(1).and_then(|r| r.split('/').next()).unwrap_or_default();
    let (group, psbt) = (text("group"), psbt_for(xpub, &text("fingerprint"))?);
    let send = |purpose: &str, marker: &str| -> Result<usize, String> {
        let intent = json!({ "group": group, "purpose": purpose,
                             "legs": [{ "kind": "psbt", "network": "regtest", "psbt": psbt }] });
        ask_and_collect(&intent, marker)?.get(0).and_then(psbt_signatures).ok_or("no signed PSBT".into())
    };
    println!("{MARK}_PSBT_SIGNED: {}", send("Doc-test: a regtest send", "REQUESTED_PSBT")?);
    std::thread::sleep(Duration::from_secs(8));
    let terms = json!({ "account": group, "password": BTC_PASSWORD, "count": 1,
                        "apps": ["signer_probe"], "confirm": true });
    ok_value(modules().signer_manager_module.unlock(&terms.to_string()))?;
    println!("{MARK}_PSBT_SIGNED_UNLOCKED: {}", send("Doc-test: a regtest send, unlocked", "REQUESTED_PSBT_UNLOCKED")?);
    Ok(())
}

/// A signature from the mock device's EVM account. The Signer approves with nothing typed; the
/// device waits for its button, which this fixture presses once the request is `signing`.
fn device_round() -> Result<(String, String), String> {
    std::thread::sleep(Duration::from_secs(8));
    let address = device_address()?;
    let sig = sign_on_device(&address, "Doc-test: sign on a device", "Signed on the device", "REQUESTED_DEVICE")?;
    Ok((address, sig))
}

/// The device's account, which the keystore now holds too: the Signer offers both, the keystore
/// first, and the person chooses the device.
fn chosen_round(address: &str) -> Result<String, String> {
    let p = json!({ "phrase": DEVICE_PHRASE, "accountIndex": 0, "password": VAULT_PASSWORD });
    ok_value(modules().keystore_module.import_mnemonic(&p.to_string()))?;
    std::thread::sleep(Duration::from_secs(2));
    sign_on_device(address, "Doc-test: the person chooses the device", "Signed on the device chosen", "REQUESTED_CHOSEN")
}

fn device_address() -> Result<String, String> {
    let listed = ok_value(modules().signer_manager_module.accounts())?;
    let address = listed
        .get("accounts")
        .and_then(Value::as_array)
        .and_then(|a| {
            a.iter().find(|x| {
                x.get("signer").and_then(Value::as_str) == Some("mock_device_signer")
                    && x.get("family").and_then(Value::as_str) == Some("evm")
            })
        })
        .and_then(|x| x.get("id").and_then(Value::as_str))
        .ok_or("the manager lists no device account")?
        .to_string();
    Ok(address)
}

/// Ask for a message signed by `address`, and press the device's button once it is `signing`.
fn sign_on_device(address: &str, purpose: &str, text: &str, marker: &str) -> Result<String, String> {
    let intent = json!({ "address": address, "purpose": purpose, "legs": [{ "kind": "message", "text": text }] });
    let v = ok_value(modules().signer_manager_module.request_approval(&intent.to_string()))?;
    let field = |k: &str| v.get(k).and_then(Value::as_str).unwrap_or_default().to_string();
    let (handle, receipt) = (field("handle"), field("receipt"));
    println!("{MARK}_{marker}: {handle}");
    let mut pressed = false;
    for _ in 0..600 {
        std::thread::sleep(Duration::from_millis(250));
        let Ok(v) = ok_value(modules().signer_manager_module.approval_status(&handle, &receipt)) else { continue };
        match v.get("state").and_then(Value::as_str) {
            // The person approved in the Signer; a moment later they confirm on the device.
            Some("signing") if !pressed => {
                std::thread::sleep(Duration::from_secs(2));
                let screen = ok_value(modules().mock_device_signer.screen())?;
                let job = screen
                    .get("waiting")
                    .and_then(|w| w.get(0))
                    .and_then(|j| j.get("job"))
                    .and_then(Value::as_str)
                    .ok_or("nothing on the device's screen")?
                    .to_string();
                ok_value(modules().mock_device_signer.press(&job, "confirm"))?;
                pressed = true;
            }
            Some("settled") => {
                let reason = v.get("reason").and_then(Value::as_str).unwrap_or("").to_string();
                if reason != "approved" {
                    return Err(reason);
                }
                let f = ok_value(modules().signer_manager_module.fetch_result(&handle, &receipt))?;
                let _ = modules().signer_manager_module.ack_result(&handle, &receipt);
                return Ok(f.get("signed").and_then(|s| s.get(0)).and_then(Value::as_str).unwrap_or("").to_string());
            }
            _ => {}
        }
    }
    Err("nobody decided the device request".into())
}

fn drive(state: Shared) {
    macro_rules! set { ($v:expr) => { *state.lock().unwrap() = $v; } }

    // Let the host finish wiring before the first outbound call.
    std::thread::sleep(Duration::from_millis(1500));

    // 1. Name every role, because configure() is total: a role the document does not
    // name is held by nobody, so leaving out the approver would refuse evm_signer_ui itself.
    let configured = ok_value(modules().keystore_module.configure(KEYSTORE_ROLES))
        .and_then(|_| ok_value(modules().signer_manager_module.configure(MANAGER_ROLES)));
    if let Err(e) = configured {
        println!("{MARK}_ERROR: configure failed: {e}");
        set!(json!({ "ok": false, "state": "configure_failed", "error": e }));
        return;
    }
    println!("{MARK}_ROLES: {KEYSTORE_ROLES} {MANAGER_ROLES}");

    // 2. Admitted only because the call above named this module the keystore's custodian.
    let address = match ok_value(modules().keystore_module.import_private_key(TEST_KEY, VAULT_PASSWORD)) {
        Ok(v) => v.get("address").and_then(Value::as_str).unwrap_or_default().to_string(),
        Err(e) => {
            println!("{MARK}_ERROR: import failed: {e}");
            set!(json!({ "ok": false, "state": "import_failed", "error": e }));
            return;
        }
    };
    println!("{MARK}_ADDRESS: {address}");

    // 3/4/5. Ask, wait, collect — and RE-ASK if nobody was listening.
    //
    // The manager gives an approver a minute to acknowledge an offer; an
    // offer nobody claims settles as `expired_no_ack`. That is
    // deliberate — it tells a requester quickly that no approver is present,
    // instead of parking a signature request forever — but it means a request
    // only survives if the signer UI is ALREADY open and polling. So a real
    // requester must do what this does: notice `expired_no_ack`, tell the user
    // to open the Signer, and offer again. Basecamp does not autoload UI
    // plugins, so the first offers of a run routinely expire.
    let intent = json!({
        "address": address,
        // Deliberately contains no form of the word "approve": the doc-test clicks
        // the Approve button by TEXT, and this purpose line is rendered in the
        // queue row, so any overlap makes the click ambiguous -- it matched the
        // row instead of the button the first time.
        "purpose": "Doc-test: sign one message end to end",
        // Three legs, one per confidence tier the sheet must show differently:
        // a message nobody can decode, a WETH `transfer` the ABI database VERIFIES,
        // and a made-up token address the database cannot hold -- so the custom
        // token list entry is the only leg an unverified list may speak about,
        // and WETH is the control that proves it stays quiet over a verified address.
        "legs": [
            { "kind": "message", "text": MESSAGE },
            { "kind": "tx", "chain_id": 1, "tx": {
                "to": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
                "value": "0",
                "nonce": "0",
                "gas_limit": "60000",
                "data": "0xa9059cbb000000000000000000000000d8da6bf26964af9d7eed9e03e53415d37aa96045000000000000000000000000000000000000000000000000000000003b9aca00"
            }},
            // 2500000 at DTEST's 6 decimals is 2.5 -- a fractional amount, and one
            // that reads as 0.0000000000025 if a surface assumes 18.
            { "kind": "tx", "chain_id": 1, "tx": {
                "to": "0x1234567890abcdef1234567890abcdef12345678",
                "value": "0",
                "nonce": "1",
                "gas_limit": "60000",
                "data": "0xa9059cbb000000000000000000000000d8da6bf26964af9d7eed9e03e53415d37aa9604500000000000000000000000000000000000000000000000000000000002625a0"
            }}
        ]
    })
    .to_string();

    let mut announced = false;
    let mut needs_approver = false;
    for _ in 0..600 {
        let (handle, receipt) = match ok_value(modules().signer_manager_module.request_approval(&intent)) {
            Ok(v) => (
                v.get("handle").and_then(Value::as_str).unwrap_or_default().to_string(),
                v.get("receipt").and_then(Value::as_str).unwrap_or_default().to_string(),
            ),
            Err(e) => {
                // Tier B refusing us is the interesting failure: it means this
                // module was not named, and the gate is doing its job.
                println!("{MARK}_ERROR: request_approval refused: {e}");
                set!(json!({ "ok": false, "state": "request_refused", "error": e }));
                return;
            }
        };
        if !announced {
            println!("{MARK}_REQUESTED: {handle}");
            announced = true;
        }
        set!(json!({ "ok": true, "state": "waiting", "address": address, "handle": handle }));

        // Poll rather than subscribe: a doc-test wants determinism more than
        // latency, and polling cannot miss a subscription edge.
        let mut outcome = String::new();
        for _ in 0..600 {
            std::thread::sleep(Duration::from_millis(250));
            let v = match ok_value(modules().signer_manager_module.approval_status(&handle, &receipt)) {
                Ok(v) => v,
                Err(_) => continue,
            };
            let state = v.get("state").and_then(Value::as_str).unwrap_or("");
            if state == "offered" || state == "rendered" {
                continue;
            }
            outcome = v.get("reason").and_then(Value::as_str).unwrap_or(state).to_string();
            break;
        }

        if outcome == "expired_no_ack" || outcome.is_empty() {
            // Nobody acknowledged inside ACK_DEADLINE, which means no approver
            // is listening. This is the ONE case a requester must surface to
            // the user, because it is the one they can fix: the Signer has to
            // be open for a signature to be possible at all. Say that, once,
            // and keep offering so it succeeds the moment they open it.
            if !needs_approver {
                needs_approver = true;
                println!("{MARK}_NEEDS_APPROVER: {NEEDS_APPROVER_MESSAGE}");
            }
            set!(json!({
                "ok": true,
                "state": "waiting_for_approver",
                "address": address,
                // What a real requester's UI binds to. The manager reports
                // `expired_no_ack`; turning that into something a human can act
                // on is the requester's job, not the signer's.
                "needs_approver": true,
                "message": NEEDS_APPROVER_MESSAGE
            }));
            continue;
        }
        if outcome != "approved" {
            println!("{MARK}_SETTLED_WITHOUT_SIGNATURE: {outcome}");
            set!(json!({ "ok": false, "state": outcome, "handle": handle }));
            return;
        }

        // Approved. The RECEIPT authorises collection, not the caller name — a
        // module that merely learned the handle from the event plane cannot
        // reach this.
        match ok_value(modules().signer_manager_module.fetch_result(&handle, &receipt)) {
            Ok(v) => {
                let signed = v.get("signed").cloned().unwrap_or(Value::Null);
                let first = signed.get(0).and_then(Value::as_str).unwrap_or("").to_string();
                println!("{MARK}_SIGNED: {first}");
                set!(json!({ "ok": true, "state": "signed", "address": address,
                             "handle": handle, "signed": signed }));
                let _ = modules().signer_manager_module.ack_result(&handle, &receipt);
                match unlocked_round(&address) {
                    Ok(sig) => println!("{MARK}_SIGNED_UNLOCKED: {sig}"),
                    Err(e) => println!("{MARK}_ERROR: unlocked round: {e}"),
                }
                if let Err(e) = bitcoin_rounds() {
                    println!("{MARK}_ERROR: Bitcoin rounds: {e}");
                }
                match device_round() {
                    Ok((device, sig)) => {
                        println!("{MARK}_DEVICE_SIGNED: {sig}");
                        match chosen_round(&device) {
                            Ok(sig) => println!("{MARK}_CHOSEN_SIGNED: {sig}"),
                            Err(e) => println!("{MARK}_ERROR: chosen round: {e}"),
                        }
                    }
                    Err(e) => println!("{MARK}_ERROR: device round: {e}"),
                }
            }
            Err(e) => {
                println!("{MARK}_ERROR: fetch_result failed: {e}");
                set!(json!({ "ok": false, "state": "fetch_failed", "error": e }));
            }
        }
        return;
    }
    println!("{MARK}_ERROR: gave up waiting for an approver");
    set!(json!({ "ok": false, "state": "no_approver" }));
}

impl SignerProbeModule for SignerProbeModuleImpl {
    fn on_context_ready(&mut self, _ctx: &RustModuleContext) {
        let state = std::sync::Arc::clone(&self.state);
        *state.lock().unwrap() = json!({ "ok": true, "state": "starting" });
        std::thread::spawn(move || drive(state));
    }

    fn status(&mut self) -> String {
        self.state.lock().unwrap().to_string()
    }
}

#[no_mangle]
pub extern "Rust" fn logos_module_install() {
    install::<SignerProbeModuleImpl>();
}
