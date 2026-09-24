import 'package:cloudtune/domain/entities/capabilities.dart';
import 'package:cloudtune/domain/entities/cloud_account.dart';
import 'package:cloudtune/domain/entities/drive_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CloudAccount make({
    String? displayName,
    DateTime? expiresAt,
    int? used,
    int? total,
  }) =>
      CloudAccount(
        provider: DriveProvider.quark,
        authMode: AuthMode.browserCookie,
        authorizedAt: DateTime(2026, 9, 23),
        displayName: displayName,
        expiresAt: expiresAt,
        storageUsedBytes: used,
        storageTotalBytes: total,
      );

  group('label', () {
    test('优先昵称', () {
      expect(make(displayName: '张三').label, '张三');
    });

    test('昵称为空或纯空白时退回网盘名', () {
      expect(make().label, '夸克网盘');
      expect(make(displayName: '').label, '夸克网盘');
      expect(make(displayName: '   ').label, '夸克网盘');
    });
  });

  group('过期判定', () {
    test('无过期时间视为不过期（Cookie 类凭证常见）', () {
      expect(make().isExpired, isFalse);
    });

    test('已过期', () {
      expect(
        make(expiresAt: DateTime.now().subtract(const Duration(hours: 1))).isExpired,
        isTrue,
      );
    });

    test('未过期', () {
      expect(
        make(expiresAt: DateTime.now().add(const Duration(hours: 1))).isExpired,
        isFalse,
      );
    });
  });

  group('容量', () {
    test('hasStorageInfo 需要总量存在且大于 0', () {
      expect(make(used: 1, total: 100).hasStorageInfo, isTrue);
      expect(make(used: 1).hasStorageInfo, isFalse);
      expect(make(used: 1, total: 0).hasStorageInfo, isFalse);
    });

    test('storageRatio 正常计算', () {
      expect(make(used: 25, total: 100).storageRatio, 0.25);
    });

    test('storageRatio 超出总量时夹到 1.0', () {
      expect(make(used: 150, total: 100).storageRatio, 1.0);
    });

    test('缺数据时 storageRatio 为 null（不产生 NaN）', () {
      expect(make(used: 1).storageRatio, isNull);
      expect(make().storageRatio, isNull);
    });
  });

  group('copyWith', () {
    test('只覆盖传入字段', () {
      final a = make(displayName: '张三', used: 1, total: 100);
      final b = a.copyWith(displayName: '李四');
      expect(b.displayName, '李四');
      expect(b.storageUsedBytes, 1);
      expect(b.provider, DriveProvider.quark);
      expect(b.authMode, AuthMode.browserCookie);
    });

    test('可补充会员标识（用于解释超限与会员无关）', () {
      final a = make().copyWith(memberLabel: 'SUPER_VIP');
      expect(a.memberLabel, 'SUPER_VIP');
    });
  });

  group('等价性', () {
    test('同网盘同用户同授权方式视为同一账号', () {
      final a = CloudAccount(
        provider: DriveProvider.quark,
        authMode: AuthMode.browserCookie,
        authorizedAt: DateTime(2026, 9, 1),
        userId: 'u1',
      );
      final b = CloudAccount(
        provider: DriveProvider.quark,
        authMode: AuthMode.browserCookie,
        authorizedAt: DateTime(2026, 9, 23),
        userId: 'u1',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('不同 userId 不相等', () {
      final a = CloudAccount(
        provider: DriveProvider.quark,
        authMode: AuthMode.browserCookie,
        authorizedAt: DateTime(2026, 9, 23),
        userId: 'u1',
      );
      final b = a.copyWith(userId: 'u2');
      expect(a == b, isFalse);
    });
  });
}
