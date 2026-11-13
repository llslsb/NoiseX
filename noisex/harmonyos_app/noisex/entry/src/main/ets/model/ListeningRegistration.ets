export function shouldStartListening(currentGeohash: string, nextGeohash: string, force: boolean): boolean {
  return force || currentGeohash !== nextGeohash;
}
