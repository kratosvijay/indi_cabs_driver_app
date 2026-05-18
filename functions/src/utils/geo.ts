/**
 * Calculate distance between two points using Haversine formula
 */
export function calculateDistance(
    lat1: number,
    lon1: number,
    lat2: number,
    lon2: number
): number {
    const R = 6371; // Radius of the Earth in km
    const dLat = ((lat2 - lat1) * Math.PI) / 180;
    const dLon = ((lon2 - lon1) * Math.PI) / 180;
    const a =
        Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos((lat1 * Math.PI) / 180) *
        Math.cos((lat2 * Math.PI) / 180) *
        Math.sin(dLon / 2) *
        Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
}

/**
 * Filter noisy GPS points based on accuracy, speed, and jumps.
 */
export function isValidPoint(
    oldP: { lat: number; lng: number; timestamp: number },
    newP: { lat: number; lng: number; timestamp: number; accuracy?: number }
): boolean {
    const distanceKm = calculateDistance(oldP.lat, oldP.lng, newP.lat, newP.lng);
    const distanceMeters = distanceKm * 1000;
    const seconds = (newP.timestamp - oldP.timestamp) / 1000;

    if (seconds <= 0) return false;

    const speedKmh = (distanceKm / (seconds / 3600));

    // 1. Accuracy Filter (Reject points with > 30m error)
    if (newP.accuracy !== undefined && newP.accuracy > 30) {
        console.log(`[GPS_FILTER] Rejected: Low accuracy (${newP.accuracy}m)`);
        return false;
    }

    // 2. Speed Spike Filter (Reject if speed > 140 km/h)
    if (speedKmh > 140) {
        console.log(`[GPS_FILTER] Rejected: Speed spike (${speedKmh.toFixed(2)} km/h)`);
        return false;
    }

    // 3. Jump Filter (Reject if moved > 300m in < 3s)
    if (distanceMeters > 300 && seconds < 3) {
        console.log(`[GPS_FILTER] Rejected: Impossible jump (${distanceMeters.toFixed(0)}m in ${seconds}s)`);
        return false;
    }

    // 4. Minimum movement filter (Ignore points < 2m to avoid drift while stationary)
    if (distanceMeters < 2) {
        return false;
    }

    return true;
}
