export const AVR_TEMPLATE = `<?xml version="1.0" encoding="UTF-8"?>
<harman>
    <avr>
        <common>
            <control>
                <name>{{ name }}</name>
                <zone>{{ zone }}</zone>
                <para>{{ para }}</para>
            </control>
        </common>
    </avr>
</harman>`;

export const BDS_TEMPLATE = `<?xml version="1.0" encoding="UTF-8"?>
<harman>
    <bds>
        <common>
            <control>
                <name>{{ name }}</name>
                <zone>{{ zone }}</zone>
                <para>{{ para }}</para>
            </control>
        </common>
    </bds>
</harman>`;

export const TEMPLATES = {
  avr: AVR_TEMPLATE,
  bds: BDS_TEMPLATE,
};
