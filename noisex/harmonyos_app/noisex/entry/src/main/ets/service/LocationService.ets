import { geoLocationManager } from '@kit.LocationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../common/Logger';
import { Utils } from '../common/Utils';
import { Constants } from '../model/Constants';

// 定位服务 + Geohash 模糊化
export class LocationService {
  private static instance: LocationService;
  private currentGeohash: string = '';
  private isRunning: boolean = false;
  public onGeohashChanged: ((geohash: string) => void) | null = null;
  private locationCallback: (location: geoLocationManager.Location) => void =
    (location: geoLocationManager.Location) => {};

  private constructor() {}

  public static getInstance(): LocationService {
    if (!LocationService.instance) {
      LocationService.instance = new LocationService();
    }
    return LocationService.instance;
  }

  public startLocation(): void {
    if (this.isRunning) return;

    const requestInfo: geoLocationManager.LocationRequest = {
      priority: geoLocationManager.LocationRequestPriority.FIRST_FIX,
      timeInterval: 60,
      distanceInterval: 100
    };

    this.locationCallback = (location: geoLocationManager.Location) => {
      const nextGeohash: string = Utils.toGeohash(
        location.latitude,
        location.longitude,
        Constants.DEFAULT_GEOHASH_PRECISION
      );
      if (nextGeohash !== this.currentGeohash) {
        this.currentGeohash = nextGeohash;
        Logger.info(`[LocationService] Geohash: ${this.currentGeohash}`);
        if (this.onGeohashChanged) {
          this.onGeohashChanged(this.currentGeohash);
        }
      }
    };

    try {
      geoLocationManager.on('locationChange', requestInfo, this.locationCallback);
      this.isRunning = true;
      Logger.info('[LocationService] Started');
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.error(`[LocationService] Start error: ${e.message}`);
    }
  }

  public stopLocation(): void {
    if (!this.isRunning) return;

    try {
      geoLocationManager.off('locationChange', this.locationCallback);
      this.isRunning = false;
      Logger.info('[LocationService] Stopped');
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.error(`[LocationService] Stop error: ${e.message}`);
    }
  }

  public getGeohash(): string {
    return this.currentGeohash;
  }

  public getIsRunning(): boolean {
    return this.isRunning;
  }
}
