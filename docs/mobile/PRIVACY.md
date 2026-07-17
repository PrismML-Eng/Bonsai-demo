# Bonsai Mobile privacy

Inference, vision preprocessing, reasoning, and the fixed calculator/date/device-information/notes tools are designed to run on the device. There is no cloud-inference fallback. Hugging Face is contacted only when the user starts model acquisition; importing a previously downloaded model does not contact Hugging Face.

## Local data ownership

- `BonsaiMobile/Models` owns verified installations, staging files, and deletion trash. `BonsaiMobile/BackgroundTransfers` owns resumable background-transfer ledgers and bodies. Installed models are excluded from device backup.
- Conversation and navigation records own local prompts, answers, reasoning, model bindings, and attachment references.
- `BonsaiMobile/Attachments` owns original images. Preprocessing uses bounded in-memory buffers and owned temporary import leases.
- Local notes are written only after the user allows a write once.
- Diagnostics use a closed content-free schema: stage, category, elapsed time, token counts/rate, thermal state, warning count, model ID/revision, and timestamp.
- A private-data-clear intent/journal finishes or rolls back an interrupted clear operation.

“Clear conversations, notes, and images” clears those three content stores as one recoverable operation. It does not delete installed models, change model download state, or publish diagnostics. Models are deleted separately in Model Library. A clear failure remains visible and retryable.

## Network boundaries and proof

Production network ownership is limited to model acquisition in the model-library transport and background-download coordinator. The inference engine and fixed offline tools do not accept URLs, register tools, execute arbitrary code, or receive a network client. Diagnostics contain no arbitrary metadata, prompt, response, attachment, path, URL, or note field.

A source audit alone cannot publish a zero-network claim. Release proof also requires a human-attested physical-device run after installation with airplane mode and Wi-Fi off, plus the same installed-model flow under an external online network inspector observing zero outbound app connections. Background downloads must be quiesced.

Offline privacy is currently unverified for release: no physical airplane-mode artifact or external capture has been committed. The deterministic UI fixture only tests observable navigation/accessibility; it cannot attest airplane mode and is not network evidence. Future content-free evidence will be linked from [DEVICE-SUPPORT.md](DEVICE-SUPPORT.md).
