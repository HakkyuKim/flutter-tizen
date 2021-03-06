import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tizen/tizen_tpk.dart';

import '../flutter/packages/flutter_tools/test/src/common.dart';

void main() {
  FileSystem fileSystem;

  setUp(() {
    fileSystem = MemoryFileSystem.test();
  });

  testWithoutContext('can parse certificate from file', () {
    final File certificateSource = fileSystem.file('profiles.xml')
      ..writeAsStringSync('''
<?xml version="1.0 encoding="UTF-8" standalone="no"?>
<profiles active="example" version="3.1">
<profile name="example">
<profileitem ca="" distributor="0" key="author.p12" password="author.pwd"/>
<profileitem ca="" distributor="1" key="distributor.p12" password="distributor.pwd"/>
<profileitem ca="" distributor="2" key="" password=""/>
</profile>
</profiles>
''')
      ..createSync();
    final CertificateProfiles certificateProfiles =
        CertificateProfiles.parseFromXml(certificateSource);

    expect(certificateProfiles.activeProfileName, 'example');
    expect(certificateProfiles.activeProfile.name, 'example');

    final Certificate authorCertificate =
        certificateProfiles.activeProfile.authorCertificate;

    expect(authorCertificate.distributorNumber, '0');
    expect(authorCertificate.key, 'author.p12');
    expect(authorCertificate.password, 'author.pwd');

    expect(certificateProfiles.activeProfile.distributorCertificates.length, 1);

    final Certificate distributorCertificate =
        certificateProfiles.activeProfile.distributorCertificates.first;
    expect(distributorCertificate.distributorNumber, '1');
    expect(distributorCertificate.key, 'distributor.p12');
    expect(distributorCertificate.password, 'distributor.pwd');
  });

  testWithoutContext(
    'can parse Samsung/Tizen certificate',
    () {
      final File certificateSource = fileSystem.file('profiles.xml')
        ..writeAsStringSync('''
<?xml version="1.0 encoding="UTF-8" standalone="no"?>
<profiles active="samsung_profile" version="3.1">
<profile name="samsung_profile">
<profileitem ca="" distributor="0" key="author.p12" password="author.pwd"/>
<profileitem ca="" distributor="1" key="distributor.p12" password="distributor.pwd"/>
<profileitem ca="" distributor="2" key="" password=""/>
</profile>
<profile name="tizen_profile">
<profileitem ca="tizen-developer-ca.cer" distributor="0" key="author.p12" password="author.pwd"/>
<profileitem ca="tizen-distributor-ca.cer" distributor="1" key="distributor.p12" password="distributor.pwd"/>
<profileitem ca="" distributor="2" key="" password=""/>
</profile>
</profiles>
''')
        ..createSync();
      final CertificateProfiles certificateProfiles =
          CertificateProfiles.parseFromXml(certificateSource);

      final CertificateProfile samsungProfile = certificateProfiles.profiles
          .firstWhere((CertificateProfile profile) => profile.isSamsungProfile);

      final CertificateProfile tizenProfile = certificateProfiles.profiles
          .firstWhere((CertificateProfile profile) => profile.isTizenProfile);

      expect(samsungProfile.name, 'samsung_profile');
      expect(tizenProfile.name, 'tizen_profile');
    },
  );

  testWithoutContext('handle empty profiles', () {
    final File certificateSource = fileSystem.file('profiles.xml')
      ..writeAsStringSync('''
<?xml version="1.0 encoding="UTF-8" standalone="no"?>
<profiles active="" version="3.1"/>
''')
      ..createSync();
    final CertificateProfiles certificateProfiles =
        CertificateProfiles.parseFromXml(certificateSource);

    expect(certificateProfiles, isNot(null));
    expect(certificateProfiles.profiles, isNot(null));

    expect(certificateProfiles.activeProfileName, null);
    expect(certificateProfiles.activeProfile, null);
  });
}
