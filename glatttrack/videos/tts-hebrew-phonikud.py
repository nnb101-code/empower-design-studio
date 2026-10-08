import sys, json, wave, numpy as np
from phonikud_tts import Phonikud, phonemize, Piper
ph = Phonikud('phonikud-1.0.int8.onnx'); piper = Piper('shaul.onnx', 'model.config.json')
items = json.load(open(sys.argv[1])); out = {}
for k, text in items.items():
    v = ph.add_diacritics(text); p = phonemize(v)
    s, sr = piper.create(p, is_phonemes=True)
    s = np.clip(np.array(s, dtype=np.float32), -1, 1); f = sys.argv[2] + '/' + k + '.wav'
    with wave.open(f, 'wb') as w: w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr); w.writeframes((s * 32767).astype('<i2').tobytes())
    out[k] = len(s) / sr; print(k, round(out[k], 1), v, flush=True)
json.dump(out, open(sys.argv[2] + '/durations.json', 'w'), indent=1)
