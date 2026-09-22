/**
 * 对齐 Flutter app/lib/config/env.dart（默认开发地址可按构建替换）
 */
export enum AppEnv {
  DEV = 0,
  PROD = 1
}

/** 与 Flutter ServiceRegion / mainland_china | international 对应 */
export enum ServiceRegion {
  MAINLAND_CHINA = 0,
  INTERNATIONAL = 1
}

export class Env {
  private static currentEnv: AppEnv = AppEnv.DEV;
  private static prodRegion: ServiceRegion = ServiceRegion.MAINLAND_CHINA;

  /** Release 构建可在入口改为 PROD */
  static setEnv(env: AppEnv): void {
    Env.currentEnv = env;
  }

  static getCurrent(): AppEnv {
    return Env.currentEnv;
  }

  static setProdRegion(region: ServiceRegion): void {
    Env.prodRegion = region;
  }

  static get apiUrl(): string {
    if (Env.currentEnv !== AppEnv.PROD) {
      return Env.DEV_API;
    }
    return Env.prodRegion === ServiceRegion.INTERNATIONAL ? Env.PROD_API_SHRIMPSEND : Env.PROD_API_XIACHUAN;
  }

  static get wukongimWs(): string {
    if (Env.currentEnv !== AppEnv.PROD) {
      return Env.DEV_WS;
    }
    if (Env.prodRegion === ServiceRegion.INTERNATIONAL) {
      return Env.PROD_WS_SHRIMPSEND;
    }
    return Env.websocketFromApi(Env.PROD_API_XIACHUAN);
  }

  static websocketFromApi(apiUrl: string): string {
    if (apiUrl.startsWith('https://')) {
      return `wss://${apiUrl.substring('https://'.length)}/wkws`;
    }
    if (apiUrl.startsWith('http://')) {
      return `ws://${apiUrl.substring('http://'.length)}/wkws`;
    }
    return `wss://${apiUrl}/wkws`;
  }

  static get label(): string {
    return Env.currentEnv === AppEnv.PROD ? '线上' : '测试';
  }

  private static readonly DEV_API = 'http://192.168.0.100:9000';
  private static readonly DEV_WS = 'ws://192.168.0.100:5200';
  private static readonly PROD_API_XIACHUAN = 'https://api.xiachuan.net';
  private static readonly PROD_API_SHRIMPSEND = 'https://api.shrimpsend.com';
  private static readonly PROD_WS_SHRIMPSEND = 'wss://api.shrimpsend.com/wkws';
}
