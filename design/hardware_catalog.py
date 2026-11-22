"""Hardware identities used by Otoha. Regional names and boxed systems resolve to the head unit."""

from dataclasses import dataclass


@dataclass(frozen=True)
class Model:
    key: str
    label: str
    form: str
    aliases: tuple = ()
    finish: str = "black"


def catalog():
    for number in ("3700", "3770"):
        yield Model("HK" + number, "HK " + number, "stereo")
    for short, long in (
        ("151", "1510"),
        ("161", "1610"),
        ("171", "1710"),
        ("170", "1700"),
        ("270", "2700"),
        ("370", "3700"),
    ):
        for suffix in ("", "S") if short.endswith("1") else ("",):
            a, b = short + suffix, long + suffix
            regional = ["AVR " + a + "/" + b]
            if short.endswith("1") and not suffix:
                regional.append("AVR " + a + "/230")
            if short.endswith("1") or short == "170":
                regional.append("AVR " + a + "/230C")
            form = "avr-" + short
            yield Model("AVR" + a, "AVR " + a, form, tuple(regional))
            yield Model("AVR" + b, "AVR " + b, form)
    kits = {
        "275": ["375", "G3"],
        "277": ["477"],
        "575": ["775"],
        "577": ["877"],
        "280": ["380", "480"],
        "580": ["680", "780", "880"],
        "280S": ["385S", "485S", "280/80S"],
        "580S": ["685S", "785S", "885S", "580/80S"],
        "235": ["335"],
        "535": ["635"],
    }
    for number, packages in kits.items():
        form = "bds-35" if number.endswith("35") else "bds-7" if number[-1] in "57" else "bds-80"
        yield Model("BDS" + number, "BDS " + number, form, tuple("BDS " + x for x in packages))
    for number, kit, form in [
        ("577", "7773W", "bds-7"),
        ("280", "480W", "bds-80"),
        ("580", "780W", "bds-80"),
    ]:
        yield Model("BDS" + number + "W", "BDS " + kit, form, finish="white")
    yield Model("Aura", "Aura", "aura", ("HK Aura", "soundtube"))
    yield Model("AuraPlus", "Aura Plus", "aura", ("HK Aura Plus",), "white")
    yield Model("Onyx", "Onyx", "onyx", ("HK Onyx",))
    for key, label, form, aliases in [
        ("RMmini3", "RM mini 3", "bean", ("RM mini",)),
        ("RMpro", "RM pro", "triangle", ("RM pro+", "RM pro/pro+", "RM plus", "RM home")),
        ("RM4mini", "RM4 mini", "mini", ("RM4S",)),
        ("RM4Cmini", "RM4C mini", "mini-c", ()),
        ("RM4pro", "RM4 pro", "pro4", ()),
        ("RM4Cpro", "RM4C pro", "pro4-c", ()),
        ("RM4TVmate", "RM4 TV mate", "mate", ("RM4C mate",)),
    ]:
        yield Model(
            key,
            "Broadlink " + label,
            form,
            tuple(
                [label, *aliases]
                + ["Broadlink " + a for a in aliases]
                + (["BestCon " + label] if label.startswith("RM4C") else [])
            ),
        )
    for key, label, form in [
        ("IP2IR", "IP2IR", "itach-ip"),
        ("WF2IR", "WF2IR", "itach-wf"),
        ("FlexIP", "Flex Ethernet", "flex-ip"),
        ("FlexPoE", "Flex PoE", "flex-poe"),
        ("FlexWiFi", "Flex WiFi", "flex-wf"),
    ]:
        yield Model(key, "Global Caché iTach " + label, form, ("iTach " + label,))
    yield Model("IRKit", "IRKit", "irkit")
    for key, label, form, code, finish in [
        ("Remo1", "1", "remo-1", "Remo-01", "white"),
        ("Remo2", "2", "remo-2", "Remo-1W2", "white"),
        ("Remo3", "3", "remo-3", "Remo-1W3", "white"),
        ("RemoMini", "mini", "remo-mini", "Remo-2W1", "white"),
        ("RemoMini2", "mini 2", "remo-mini2", "Remo-2W2", "white"),
        ("RemoBlack", "mini 2 Premium Black", "remo-mini2", "Remo-2B2", "black"),
        ("RemoBlue", "mini 2 Premium Nature Blue", "remo-mini2", "Remo-2N2", "blue"),
    ]:
        aliases = (code, "Nature Remo") if key == "Remo3" else (code,)
        yield Model(key, "Nature Remo " + label, form, aliases, finish)
    yield Model("TasmotaIR", "Tasmota IR", "board")
