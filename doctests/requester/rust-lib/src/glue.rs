//! The requester half of the signer UI's end-to-end proof.
//!
//! Sequence, all of it Tier B or Tier C — this module can ASK but can never
//! APPROVE, and that is the property under test:
//!
//!   1. import a known private key            (Tier C, ungated)
//!   2. request_approval for a message        (Tier B, named modules only)
//!   3. poll approval_status until it settles (Tier B, receipt-gated)
//!   4. fetch_result, print the signature     (Tier B, receipt-gated)
//!
//! Nothing here can reach `approve()`. The signature this prints exists only
//! because a human typed the vault password into the signer UI.
//!
//! The work runs on its own thread rather than in `on_context_ready`, so the
//! first outbound call cannot re-enter the host while this module is still
//! initialising. Outbound calls are marshalled by the SDK, so calling from a
//! worker thread is supported.

use serde_json::{json, Value};
use std::time::Duration;

/// Fully qualified rather than imported: the generated scaffold is `include!`d
/// into this module and brings its own `Arc`/`Mutex` into scope.
type Shared = std::sync::Arc<std::sync::Mutex<Value>>;

/// Foundry's well-known account 0. A published test key: never fund it.
const TEST_KEY: &str = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
const VAULT_PASSWORD: &str = "doctest-pw";
const MESSAGE: &str = "I authorise the doc-test transfer";

/// Printed on stdout so the doc-test can assert on the app log without needing
/// a CLI — Basecamp has none.
const MARK: &str = "SIGNER_PROBE";

/// What a requester tells the user when an offer expires unacknowledged. The
/// keystore's `expired_no_ack` is a protocol fact; this is the human sentence
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

fn drive(state: Shared) {
    macro_rules! set { ($v:expr) => { *state.lock().unwrap() = $v; } }

    // Let the host finish wiring before the first outbound call.
    std::thread::sleep(Duration::from_millis(1500));

    // 1. Tier C — ungated account management.
    let address = match ok_value(modules().keystore_module.import_private_key(TEST_KEY, VAULT_PASSWORD)) {
        Ok(v) => v.get("address").and_then(Value::as_str).unwrap_or_default().to_string(),
        Err(e) => {
            println!("{MARK}_ERROR: import failed: {e}");
            set!(json!({ "ok": false, "state": "import_failed", "error": e }));
            return;
        }
    };
    println!("{MARK}_ADDRESS: {address}");

    // 2/3/4. Ask, wait, collect — and RE-ASK if nobody was listening.
    //
    // The keystore gives an approver ACK_DEADLINE (3 s) to acknowledge an
    // offer; an offer nobody claims settles as `expired_no_ack`. That is
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
        // A message leg AND a transaction leg. The transaction is what gives the
        // signer UI something to decode: a WETH `transfer`, which its embedded
        // ABI database can name and therefore mark VERIFIED. The message leg
        // stays because it is decodable by nobody, and the sheet must show both.
        "legs": [
            { "kind": "message", "text": MESSAGE },
            { "kind": "tx", "chain_id": 1, "tx": {
                "to": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
                "value": "0",
                "nonce": "0",
                "gas_limit": "60000",
                "data": "0xa9059cbb000000000000000000000000d8da6bf26964af9d7eed9e03e53415d37aa96045000000000000000000000000000000000000000000000000000000003b9aca00"
            }}
        ]
    })
    .to_string();

    let mut announced = false;
    let mut needs_approver = false;
    for _ in 0..600 {
        let (handle, receipt) = match ok_value(modules().keystore_module.request_approval(&intent)) {
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
            let v = match ok_value(modules().keystore_module.approval_status(&handle, &receipt)) {
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
                // What a real requester's UI binds to. The keystore reports
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
        match ok_value(modules().keystore_module.fetch_result(&handle, &receipt)) {
            Ok(v) => {
                let signed = v.get("signed").cloned().unwrap_or(Value::Null);
                let first = signed.get(0).and_then(Value::as_str).unwrap_or("").to_string();
                println!("{MARK}_SIGNED: {first}");
                set!(json!({ "ok": true, "state": "signed", "address": address,
                             "handle": handle, "signed": signed }));
                let _ = modules().keystore_module.ack_result(&handle, &receipt);
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
