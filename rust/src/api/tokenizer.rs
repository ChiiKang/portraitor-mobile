//! DeBERTa-v3 SentencePiece tokenizer via the HF `tokenizers` crate, loading the
//! model's `tokenizer.json`. Produces byte-identical token IDs to the browser
//! (transformers.js) — golden cases in `assets/tokenizer/tokenizer_cases.json`,
//! asserted on real hardware by `integration_test/tokenizer_parity_test.dart`.
//! Exposed to Dart as an opaque `GlinerTokenizer` by flutter_rust_bridge.

use tokenizers::Tokenizer;

pub struct GlinerTokenizer {
    inner: Tokenizer,
}

impl GlinerTokenizer {
    /// Load a tokenizer from a `tokenizer.json` file path (on-device path).
    #[flutter_rust_bridge::frb(sync)]
    pub fn load(tokenizer_json_path: String) -> Result<GlinerTokenizer, String> {
        let inner = Tokenizer::from_file(&tokenizer_json_path).map_err(|e| e.to_string())?;
        Ok(GlinerTokenizer { inner })
    }

    /// Encode `text` to token IDs (no special tokens — GLiNER adds its own).
    #[flutter_rust_bridge::frb(sync)]
    pub fn encode(&self, text: String) -> Result<Vec<u32>, String> {
        let enc = self
            .inner
            .encode(text.as_str(), false)
            .map_err(|e| e.to_string())?;
        Ok(enc.get_ids().to_vec())
    }
}
