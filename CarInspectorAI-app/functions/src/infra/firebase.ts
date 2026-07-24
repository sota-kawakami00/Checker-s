/**
 * Firestore / Storage の本番アダプタ（core/ports.ts の実装）。
 * コレクション構造は schemas/firestore_collections.md が正。
 * 本ファイルは Firebase Emulator Suite での統合テスト対象（08 §1）であり、
 * ユニットテストではフェイク実装（test/helpers/fakes.ts）を用いる。
 */

import type { Firestore } from "firebase-admin/firestore";
import type { Storage } from "firebase-admin/storage";
import type {
  AppraisalRepository,
  ImageContent,
  MarketCacheRepository,
  MasterRepository,
  QuotaCounters,
  QuotaStore,
  StorageGateway,
} from "../core/ports";
import type {
  AppraisalDocument,
  CheckItemMaster,
  MarketCacheEntry,
  PhotoQualityResult,
  StoreSettings,
} from "../core/types";

function appraisalPath(storeId: string, appraisalId: string): string {
  return `stores/${storeId}/appraisals/${appraisalId}`;
}

export class FirestoreAppraisalRepository implements AppraisalRepository {
  constructor(private readonly db: Firestore) {}

  async get(
    storeId: string,
    appraisalId: string,
  ): Promise<AppraisalDocument | null> {
    const snap = await this.db.doc(appraisalPath(storeId, appraisalId)).get();
    return snap.exists ? (snap.data() as AppraisalDocument) : null;
  }

  async update(
    storeId: string,
    appraisalId: string,
    patch: Partial<AppraisalDocument>,
  ): Promise<void> {
    await this.db
      .doc(appraisalPath(storeId, appraisalId))
      .set(patch, { merge: true });
  }

  async updatePhotoCloudQuality(
    storeId: string,
    appraisalId: string,
    photoId: string,
    quality: PhotoQualityResult,
  ): Promise<void> {
    // photos は配列フィールドのためトランザクションで read-modify-write する
    const ref = this.db.doc(appraisalPath(storeId, appraisalId));
    await this.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return;
      const doc = snap.data() as AppraisalDocument;
      const photos = doc.photos.map((p) =>
        p.photoId === photoId ? { ...p, cloudQuality: quality } : p,
      );
      tx.update(ref, { photos });
    });
  }
}

export class FirestoreMarketCacheRepository implements MarketCacheRepository {
  constructor(private readonly db: Firestore) {}

  async get(cacheKey: string): Promise<MarketCacheEntry | null> {
    const snap = await this.db.doc(`marketCache/${cacheKey}`).get();
    return snap.exists ? (snap.data() as MarketCacheEntry) : null;
  }

  async set(entry: MarketCacheEntry): Promise<void> {
    await this.db.doc(`marketCache/${entry.key}`).set(entry);
  }
}

export class FirestoreMasterRepository implements MasterRepository {
  constructor(private readonly db: Firestore) {}

  async checkItems(): Promise<CheckItemMaster[]> {
    const snap = await this.db.collection("masters/checkItems/items").get();
    return snap.docs.map((d) => {
      const data = d.data() as Omit<CheckItemMaster, "code">;
      return { code: d.id, ...data };
    });
  }

  async storeSettings(storeId: string): Promise<StoreSettings | null> {
    const snap = await this.db.doc(`stores/${storeId}`).get();
    if (!snap.exists) return null;
    const data = snap.data() as { settings?: StoreSettings };
    return data.settings ?? null;
  }
}

/**
 * store 単位クォータカウンタ（05 §7）。
 * 内部運用コレクション aiQuota/{storeId}（firestore_collections.md 対象外の
 * CF 専用内部データ。クライアントからは Security Rules で読み書き不可とする想定）。
 */
export class FirestoreQuotaStore implements QuotaStore {
  constructor(private readonly db: Firestore) {}

  async increment(
    storeId: string,
    minuteBucket: string,
    dayBucket: string,
  ): Promise<QuotaCounters> {
    const ref = this.db.doc(`aiQuota/${storeId}`);
    return this.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const data = (snap.data() ?? {}) as {
        minuteBucket?: string;
        minuteCount?: number;
        dayBucket?: string;
        dayCount?: number;
      };
      const minuteCount =
        (data.minuteBucket === minuteBucket ? (data.minuteCount ?? 0) : 0) + 1;
      const dayCount =
        (data.dayBucket === dayBucket ? (data.dayCount ?? 0) : 0) + 1;
      tx.set(ref, { minuteBucket, minuteCount, dayBucket, dayCount });
      return { minuteCount, dayCount };
    });
  }
}

export class CloudStorageGateway implements StorageGateway {
  constructor(private readonly storage: Storage) {}

  async exists(storagePath: string): Promise<boolean> {
    const [exists] = await this.storage.bucket().file(storagePath).exists();
    return exists;
  }

  async download(storagePath: string): Promise<ImageContent> {
    const file = this.storage.bucket().file(storagePath);
    const [buffer] = await file.download();
    // Storage パス規約上、画像は JPEG のみ（firestore_collections.md）
    return { base64Data: buffer.toString("base64"), mimeType: "image/jpeg" };
  }
}
