//! signer_probe — the doc-test's requester.
//!
//! It exists to make the signer UI's end-to-end path real: something has to ASK
//! for a signature, and it must be a named module, because Tier B refuses the
//! host anchor and therefore refuses the CLI.
#[cfg(feature = "logos_module")]
mod glue;
