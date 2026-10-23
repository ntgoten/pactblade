# Pactblade's own sound bank for DD2 (Wwise bank version 140), built from a small game bank as the template.
#   template: ch221000_fx_es.sbnk (events / actions / sounds) + ch221000_fx_m.sbnk (media) - a monster's projectile sounds
#   ours:     pactblade_fx_es.sbnk + pactblade_fx_m.sbnk - every object id, the bank ids and the media ids are new (no clash
#             with the monster's own bank); the sounds play OUR audio as uncompressed PCM (plugin 0x00010001).
#   group "charge": the RanSeq 921405723 (4 sounds) -> our charge audio; every other sound -> our hit audio.
# Usage: python -I build_bank.py <template dir> <out dir> <charge.wav> <hit.wav>   (prints the new trigger / event ids)
import struct, sys, os, wave, json

TPL, OUT, CHARGE, HIT = sys.argv[1:5]


def fnv1(s):
    h = 2166136261
    for c in s.lower().encode():
        h = (h * 16777619) & 0xffffffff
        h ^= c
    return h


def chunks(b):
    i, out = 0, []
    while i + 8 <= len(b):
        tag, size = b[i:i + 4], struct.unpack_from('<I', b, i + 4)[0]
        out.append((tag, b[i + 8:i + 8 + size]))
        i += 8 + size
    return out


def chunk(tag, data):
    return tag + struct.pack('<I', len(data)) + data


def pcm_wem(path):
    # a Wwise PCM .wem: RIFF / WAVE, fmt = WAVE_FORMAT_EXTENSIBLE (0xFFFE, 24 bytes, Wwise channel config), data
    w = wave.open(path)
    ch, rate, bits = w.getnchannels(), w.getframerate(), w.getsampwidth() * 8
    frames = w.readframes(w.getnframes())
    assert bits == 16, 'needs 16-bit audio'
    align = ch * 2
    layout = {1: (0x4 << 12) | (1 << 8) | 1, 2: (0x3 << 12) | (1 << 8) | 2}[ch]   # mono: centre, stereo: left + right
    fmt = struct.pack('<HHIIHHHHI', 0xFFFE, ch, rate, rate * align, align, 16, 6, 0, layout)
    body = b'WAVE' + chunk(b'fmt ', fmt) + chunk(b'data', frames)
    return b'RIFF' + struct.pack('<I', len(body)) + body, w.getnframes() / rate


es_t = open(os.path.join(TPL, 'ch221000_fx_es.sbnk.1.x64'), 'rb').read()
m_t = open(os.path.join(TPL, 'ch221000_fx_m.sbnk.1.x64'), 'rb').read()
ES_OLD, M_OLD = fnv1('ch221000_fx_es'), fnv1('ch221000_fx_m')
ES_NEW, M_NEW = fnv1('pactblade_fx_es'), fnv1('pactblade_fx_m')
WEM_CHARGE, WEM_HIT = fnv1('pactblade_smite_charge_wem'), fnv1('pactblade_smite_hit_wem')
CHARGE_GROUP = {277936673, 596867046, 786604595, 854677182}   # the sounds of RanSeq 921405723 (trigger 3870869112)

wem_c, dur_c = pcm_wem(CHARGE)
wem_h, dur_h = pcm_wem(HIT)

# --- the event bank: every HIRC object under a new id, the sounds pointed at our audio
objs = []
for tag, data in chunks(es_t):
    if tag == b'HIRC':
        n = struct.unpack_from('<I', data, 0)[0]
        j = 4
        for _ in range(n):
            t = data[j]
            sz, oid = struct.unpack_from('<II', data, j + 1)
            objs.append([t, oid, bytearray(data[j + 9:j + 5 + sz])])
            j += 5 + sz
idmap = {oid: fnv1('pactblade_obj_%d' % oid) for _, oid, _ in objs}
idmap[ES_OLD], idmap[M_OLD] = ES_NEW, M_NEW
for o in objs:
    d = o[2]
    for old, new in idmap.items():   # every reference (parents, children, action targets, bank ids)
        po, pn = struct.pack('<I', old), struct.pack('<I', new)
        k = d.find(po)
        while k >= 0:
            d[k:k + 4] = pn
            k = d.find(po, k + 4)
    if o[0] == 2:   # a sound: plugin PCM, data in a bank, our media id + size
        mine = o[1] in CHARGE_GROUP
        wid, size = (WEM_CHARGE, len(wem_c)) if mine else (WEM_HIT, len(wem_h))
        struct.pack_into('<IBII', d, 0, 0x00010001, 0, wid, size)
    o[1] = idmap[o[1]]
hirc = struct.pack('<I', len(objs)) + b''.join(bytes([t]) + struct.pack('<II', len(d) + 4, oid) + bytes(d) for t, oid, d in objs)
es_out = b''
for tag, data in chunks(es_t):
    if tag == b'BKHD':
        data = bytearray(data); struct.pack_into('<I', data, 4, ES_NEW); data = bytes(data)
    elif tag == b'HIRC':
        data = hirc
    es_out += chunk(tag, data)

# --- the media bank: our two .wem, 16-byte aligned
didx, blob = b'', b''
for wid, w in ((WEM_CHARGE, wem_c), (WEM_HIT, wem_h)):
    while len(blob) % 16: blob += b'\0'
    didx += struct.pack('<III', wid, len(blob), len(w))
    blob += w
m_out = b''
for tag, data in chunks(m_t):
    if tag == b'BKHD':
        data = bytearray(data); struct.pack_into('<I', data, 4, M_NEW); data = bytes(data)
    elif tag == b'DIDX':
        data = didx
    elif tag == b'DATA':
        data = blob
    m_out += chunk(tag, data)

os.makedirs(OUT, exist_ok=True)
open(os.path.join(OUT, 'pactblade_fx_es.sbnk.1.x64'), 'wb').write(es_out)
open(os.path.join(OUT, 'pactblade_fx_m.sbnk.1.x64'), 'wb').write(m_out)
# the game triggers -> our events (the template trigger list maps trigger -> event)
EVENTS = {3870869112: 2302967703, 2250414418: 1689269294, 4215563712: 1570148630, 1079711464: 2836569262}
TRIG_NEW = {3870869112: fnv1('pactblade_trigger_smite_charge'), 2250414418: fnv1('pactblade_trigger_smite_hit'),
            4215563712: fnv1('pactblade_trigger_spare_1'), 1079711464: fnv1('pactblade_trigger_spare_2')}
info = {'es_bank': ES_NEW, 'm_bank': M_NEW, 'charge_seconds': dur_c, 'hit_seconds': dur_h,
        'triggers': {str(t): {'new_trigger': TRIG_NEW[t], 'old_event': e, 'new_event': idmap[e]} for t, e in EVENTS.items()},
        'charge_trigger': TRIG_NEW[3870869112], 'hit_trigger': TRIG_NEW[2250414418]}
json.dump(info, open(os.path.join(OUT, 'pactblade_sound_ids.json'), 'w'), indent=1)
print(json.dumps(info, indent=1))
print('es %d B, m %d B (charge %.2f s, hit %.2f s)' % (len(es_out), len(m_out), dur_c, dur_h))
