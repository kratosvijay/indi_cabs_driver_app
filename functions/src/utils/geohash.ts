/**
 * Geohash encoding/decoding utility
 * Implementation adapted for precision and simplicity
 */

const BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz";

/**
 * Encodes latitude/longitude to geohash of given precision
 * @param lat Latitude
 * @param lon Longitude
 * @param precision Number of characters in resulting geohash
 * @returns Geohash string
 */
export function encode(lat: number, lon: number, precision: number = 6): string {
    let idx = 0; // index into base32 map
    let bit = 0; // each char holds 5 bits
    let evenBit = true;
    let geohash = "";

    let latMin = -90, latMax = 90;
    let lonMin = -180, lonMax = 180;

    while (geohash.length < precision) {
        if (evenBit) {
            // Bisect E-W longitude
            const lonMid = (lonMin + lonMax) / 2;
            if (lon >= lonMid) {
                idx = idx * 2 + 1;
                lonMin = lonMid;
            } else {
                idx = idx * 2;
                lonMax = lonMid;
            }
        } else {
            // Bisect N-S latitude
            const latMid = (latMin + latMax) / 2;
            if (lat >= latMid) {
                idx = idx * 2 + 1;
                latMin = latMid;
            } else {
                idx = idx * 2;
                latMax = latMid;
            }
        }
        evenBit = !evenBit;

        if (++bit == 5) {
            // 5 bits gives us a character: append it and start over
            geohash += BASE32.charAt(idx);
            bit = 0;
            idx = 0;
        }
    }

    return geohash;
}

/**
 * Decode geohash to latitude/longitude (center of the bounding box)
 * @param geohash Geohash string
 * @returns Object with lat, lon
 */
export function decode(geohash: string): { lat: number; lon: number } {
    let evenBit = true;
    let latMin = -90, latMax = 90;
    let lonMin = -180, lonMax = 180;

    for (let i = 0; i < geohash.length; i++) {
        const chr = geohash.charAt(i);
        const idx = BASE32.indexOf(chr);
        if (idx == -1) throw new Error("Invalid geohash");

        for (let n = 4; n >= 0; n--) {
            const bitN = (idx >> n) & 1;
            if (evenBit) {
                // longitude
                const lonMid = (lonMin + lonMax) / 2;
                if (bitN == 1) {
                    lonMin = lonMid;
                } else {
                    lonMax = lonMid;
                }
            } else {
                // latitude
                const latMid = (latMin + latMax) / 2;
                if (bitN == 1) {
                    latMin = latMid;
                } else {
                    latMax = latMid;
                }
            }
            evenBit = !evenBit;
        }
    }

    return { lat: (latMin + latMax) / 2, lon: (lonMin + lonMax) / 2 };
}
