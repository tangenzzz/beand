// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $BeansTable extends Beans with TableInfo<$BeansTable, Bean> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BeansTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _syncIdMeta = const VerificationMeta('syncId');
  @override
  late final GeneratedColumn<String> syncId = GeneratedColumn<String>(
    'sync_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
    clientDefault: newSyncId,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    clientDefault: () => clock.now().millisecondsSinceEpoch,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<String> syncState = GeneratedColumn<String>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(SyncState.pending),
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roasterMeta = const VerificationMeta(
    'roaster',
  );
  @override
  late final GeneratedColumn<String> roaster = GeneratedColumn<String>(
    'roaster',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _roastDateMeta = const VerificationMeta(
    'roastDate',
  );
  @override
  late final GeneratedColumn<DateTime> roastDate = GeneratedColumn<DateTime>(
    'roast_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isBlendMeta = const VerificationMeta(
    'isBlend',
  );
  @override
  late final GeneratedColumn<bool> isBlend = GeneratedColumn<bool>(
    'is_blend',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_blend" IN (0, 1))',
    ),
  );
  static const VerificationMeta _roastedForMeta = const VerificationMeta(
    'roastedFor',
  );
  @override
  late final GeneratedColumn<String> roastedFor = GeneratedColumn<String>(
    'roasted_for',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _roastLevelMeta = const VerificationMeta(
    'roastLevel',
  );
  @override
  late final GeneratedColumn<String> roastLevel = GeneratedColumn<String>(
    'roast_level',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _countryMeta = const VerificationMeta(
    'country',
  );
  @override
  late final GeneratedColumn<String> country = GeneratedColumn<String>(
    'country',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _processingMeta = const VerificationMeta(
    'processing',
  );
  @override
  late final GeneratedColumn<String> processing = GeneratedColumn<String>(
    'processing',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _varietyMeta = const VerificationMeta(
    'variety',
  );
  @override
  late final GeneratedColumn<String> variety = GeneratedColumn<String>(
    'variety',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _producerMeta = const VerificationMeta(
    'producer',
  );
  @override
  late final GeneratedColumn<String> producer = GeneratedColumn<String>(
    'producer',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _weightGramsMeta = const VerificationMeta(
    'weightGrams',
  );
  @override
  late final GeneratedColumn<double> weightGrams = GeneratedColumn<double>(
    'weight_grams',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tasteMeta = const VerificationMeta('taste');
  @override
  late final GeneratedColumn<String> taste = GeneratedColumn<String>(
    'taste',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _costMeta = const VerificationMeta('cost');
  @override
  late final GeneratedColumn<double> cost = GeneratedColumn<double>(
    'cost',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _photoPathMeta = const VerificationMeta(
    'photoPath',
  );
  @override
  late final GeneratedColumn<String> photoPath = GeneratedColumn<String>(
    'photo_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _photoBlobMeta = const VerificationMeta(
    'photoBlob',
  );
  @override
  late final GeneratedColumn<String> photoBlob = GeneratedColumn<String>(
    'photo_blob',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isFrozenMeta = const VerificationMeta(
    'isFrozen',
  );
  @override
  late final GeneratedColumn<bool> isFrozen = GeneratedColumn<bool>(
    'is_frozen',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_frozen" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _thawedDateMeta = const VerificationMeta(
    'thawedDate',
  );
  @override
  late final GeneratedColumn<DateTime> thawedDate = GeneratedColumn<DateTime>(
    'thawed_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _emptiedAtMeta = const VerificationMeta(
    'emptiedAt',
  );
  @override
  late final GeneratedColumn<DateTime> emptiedAt = GeneratedColumn<DateTime>(
    'emptied_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    syncId,
    updatedAt,
    deviceId,
    syncState,
    id,
    name,
    roaster,
    roastDate,
    isBlend,
    roastedFor,
    roastLevel,
    country,
    processing,
    variety,
    producer,
    weightGrams,
    taste,
    cost,
    photoPath,
    photoBlob,
    isFrozen,
    thawedDate,
    emptiedAt,
    createdAt,
    deleted,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'beans';
  @override
  VerificationContext validateIntegrity(
    Insertable<Bean> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('sync_id')) {
      context.handle(
        _syncIdMeta,
        syncId.isAcceptableOrUnknown(data['sync_id']!, _syncIdMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('roaster')) {
      context.handle(
        _roasterMeta,
        roaster.isAcceptableOrUnknown(data['roaster']!, _roasterMeta),
      );
    }
    if (data.containsKey('roast_date')) {
      context.handle(
        _roastDateMeta,
        roastDate.isAcceptableOrUnknown(data['roast_date']!, _roastDateMeta),
      );
    }
    if (data.containsKey('is_blend')) {
      context.handle(
        _isBlendMeta,
        isBlend.isAcceptableOrUnknown(data['is_blend']!, _isBlendMeta),
      );
    }
    if (data.containsKey('roasted_for')) {
      context.handle(
        _roastedForMeta,
        roastedFor.isAcceptableOrUnknown(data['roasted_for']!, _roastedForMeta),
      );
    }
    if (data.containsKey('roast_level')) {
      context.handle(
        _roastLevelMeta,
        roastLevel.isAcceptableOrUnknown(data['roast_level']!, _roastLevelMeta),
      );
    }
    if (data.containsKey('country')) {
      context.handle(
        _countryMeta,
        country.isAcceptableOrUnknown(data['country']!, _countryMeta),
      );
    }
    if (data.containsKey('processing')) {
      context.handle(
        _processingMeta,
        processing.isAcceptableOrUnknown(data['processing']!, _processingMeta),
      );
    }
    if (data.containsKey('variety')) {
      context.handle(
        _varietyMeta,
        variety.isAcceptableOrUnknown(data['variety']!, _varietyMeta),
      );
    }
    if (data.containsKey('producer')) {
      context.handle(
        _producerMeta,
        producer.isAcceptableOrUnknown(data['producer']!, _producerMeta),
      );
    }
    if (data.containsKey('weight_grams')) {
      context.handle(
        _weightGramsMeta,
        weightGrams.isAcceptableOrUnknown(
          data['weight_grams']!,
          _weightGramsMeta,
        ),
      );
    }
    if (data.containsKey('taste')) {
      context.handle(
        _tasteMeta,
        taste.isAcceptableOrUnknown(data['taste']!, _tasteMeta),
      );
    }
    if (data.containsKey('cost')) {
      context.handle(
        _costMeta,
        cost.isAcceptableOrUnknown(data['cost']!, _costMeta),
      );
    }
    if (data.containsKey('photo_path')) {
      context.handle(
        _photoPathMeta,
        photoPath.isAcceptableOrUnknown(data['photo_path']!, _photoPathMeta),
      );
    }
    if (data.containsKey('photo_blob')) {
      context.handle(
        _photoBlobMeta,
        photoBlob.isAcceptableOrUnknown(data['photo_blob']!, _photoBlobMeta),
      );
    }
    if (data.containsKey('is_frozen')) {
      context.handle(
        _isFrozenMeta,
        isFrozen.isAcceptableOrUnknown(data['is_frozen']!, _isFrozenMeta),
      );
    }
    if (data.containsKey('thawed_date')) {
      context.handle(
        _thawedDateMeta,
        thawedDate.isAcceptableOrUnknown(data['thawed_date']!, _thawedDateMeta),
      );
    }
    if (data.containsKey('emptied_at')) {
      context.handle(
        _emptiedAtMeta,
        emptiedAt.isAcceptableOrUnknown(data['emptied_at']!, _emptiedAtMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Bean map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Bean(
      syncId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      ),
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_state'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      roaster: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}roaster'],
      ),
      roastDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}roast_date'],
      ),
      isBlend: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_blend'],
      ),
      roastedFor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}roasted_for'],
      ),
      roastLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}roast_level'],
      ),
      country: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}country'],
      ),
      processing: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}processing'],
      ),
      variety: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}variety'],
      ),
      producer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}producer'],
      ),
      weightGrams: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}weight_grams'],
      ),
      taste: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}taste'],
      ),
      cost: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}cost'],
      ),
      photoPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photo_path'],
      ),
      photoBlob: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photo_blob'],
      ),
      isFrozen: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_frozen'],
      )!,
      thawedDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}thawed_date'],
      ),
      emptiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}emptied_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
    );
  }

  @override
  $BeansTable createAlias(String alias) {
    return $BeansTable(attachedDatabase, alias);
  }
}

class Bean extends DataClass implements Insertable<Bean> {
  final String syncId;
  final int updatedAt;
  final String? deviceId;
  final String syncState;
  final int id;
  final String name;
  final String? roaster;
  final DateTime? roastDate;
  final bool? isBlend;
  final String? roastedFor;
  final String? roastLevel;
  final String? country;
  final String? processing;
  final String? variety;
  final String? producer;
  final double? weightGrams;
  final String? taste;
  final double? cost;
  final String? photoPath;
  final String? photoBlob;
  final bool isFrozen;
  final DateTime? thawedDate;
  final DateTime? emptiedAt;
  final DateTime createdAt;
  final bool deleted;
  const Bean({
    required this.syncId,
    required this.updatedAt,
    this.deviceId,
    required this.syncState,
    required this.id,
    required this.name,
    this.roaster,
    this.roastDate,
    this.isBlend,
    this.roastedFor,
    this.roastLevel,
    this.country,
    this.processing,
    this.variety,
    this.producer,
    this.weightGrams,
    this.taste,
    this.cost,
    this.photoPath,
    this.photoBlob,
    required this.isFrozen,
    this.thawedDate,
    this.emptiedAt,
    required this.createdAt,
    required this.deleted,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['sync_id'] = Variable<String>(syncId);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deviceId != null) {
      map['device_id'] = Variable<String>(deviceId);
    }
    map['sync_state'] = Variable<String>(syncState);
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || roaster != null) {
      map['roaster'] = Variable<String>(roaster);
    }
    if (!nullToAbsent || roastDate != null) {
      map['roast_date'] = Variable<DateTime>(roastDate);
    }
    if (!nullToAbsent || isBlend != null) {
      map['is_blend'] = Variable<bool>(isBlend);
    }
    if (!nullToAbsent || roastedFor != null) {
      map['roasted_for'] = Variable<String>(roastedFor);
    }
    if (!nullToAbsent || roastLevel != null) {
      map['roast_level'] = Variable<String>(roastLevel);
    }
    if (!nullToAbsent || country != null) {
      map['country'] = Variable<String>(country);
    }
    if (!nullToAbsent || processing != null) {
      map['processing'] = Variable<String>(processing);
    }
    if (!nullToAbsent || variety != null) {
      map['variety'] = Variable<String>(variety);
    }
    if (!nullToAbsent || producer != null) {
      map['producer'] = Variable<String>(producer);
    }
    if (!nullToAbsent || weightGrams != null) {
      map['weight_grams'] = Variable<double>(weightGrams);
    }
    if (!nullToAbsent || taste != null) {
      map['taste'] = Variable<String>(taste);
    }
    if (!nullToAbsent || cost != null) {
      map['cost'] = Variable<double>(cost);
    }
    if (!nullToAbsent || photoPath != null) {
      map['photo_path'] = Variable<String>(photoPath);
    }
    if (!nullToAbsent || photoBlob != null) {
      map['photo_blob'] = Variable<String>(photoBlob);
    }
    map['is_frozen'] = Variable<bool>(isFrozen);
    if (!nullToAbsent || thawedDate != null) {
      map['thawed_date'] = Variable<DateTime>(thawedDate);
    }
    if (!nullToAbsent || emptiedAt != null) {
      map['emptied_at'] = Variable<DateTime>(emptiedAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['deleted'] = Variable<bool>(deleted);
    return map;
  }

  BeansCompanion toCompanion(bool nullToAbsent) {
    return BeansCompanion(
      syncId: Value(syncId),
      updatedAt: Value(updatedAt),
      deviceId: deviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceId),
      syncState: Value(syncState),
      id: Value(id),
      name: Value(name),
      roaster: roaster == null && nullToAbsent
          ? const Value.absent()
          : Value(roaster),
      roastDate: roastDate == null && nullToAbsent
          ? const Value.absent()
          : Value(roastDate),
      isBlend: isBlend == null && nullToAbsent
          ? const Value.absent()
          : Value(isBlend),
      roastedFor: roastedFor == null && nullToAbsent
          ? const Value.absent()
          : Value(roastedFor),
      roastLevel: roastLevel == null && nullToAbsent
          ? const Value.absent()
          : Value(roastLevel),
      country: country == null && nullToAbsent
          ? const Value.absent()
          : Value(country),
      processing: processing == null && nullToAbsent
          ? const Value.absent()
          : Value(processing),
      variety: variety == null && nullToAbsent
          ? const Value.absent()
          : Value(variety),
      producer: producer == null && nullToAbsent
          ? const Value.absent()
          : Value(producer),
      weightGrams: weightGrams == null && nullToAbsent
          ? const Value.absent()
          : Value(weightGrams),
      taste: taste == null && nullToAbsent
          ? const Value.absent()
          : Value(taste),
      cost: cost == null && nullToAbsent ? const Value.absent() : Value(cost),
      photoPath: photoPath == null && nullToAbsent
          ? const Value.absent()
          : Value(photoPath),
      photoBlob: photoBlob == null && nullToAbsent
          ? const Value.absent()
          : Value(photoBlob),
      isFrozen: Value(isFrozen),
      thawedDate: thawedDate == null && nullToAbsent
          ? const Value.absent()
          : Value(thawedDate),
      emptiedAt: emptiedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(emptiedAt),
      createdAt: Value(createdAt),
      deleted: Value(deleted),
    );
  }

  factory Bean.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Bean(
      syncId: serializer.fromJson<String>(json['syncId']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deviceId: serializer.fromJson<String?>(json['deviceId']),
      syncState: serializer.fromJson<String>(json['syncState']),
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      roaster: serializer.fromJson<String?>(json['roaster']),
      roastDate: serializer.fromJson<DateTime?>(json['roastDate']),
      isBlend: serializer.fromJson<bool?>(json['isBlend']),
      roastedFor: serializer.fromJson<String?>(json['roastedFor']),
      roastLevel: serializer.fromJson<String?>(json['roastLevel']),
      country: serializer.fromJson<String?>(json['country']),
      processing: serializer.fromJson<String?>(json['processing']),
      variety: serializer.fromJson<String?>(json['variety']),
      producer: serializer.fromJson<String?>(json['producer']),
      weightGrams: serializer.fromJson<double?>(json['weightGrams']),
      taste: serializer.fromJson<String?>(json['taste']),
      cost: serializer.fromJson<double?>(json['cost']),
      photoPath: serializer.fromJson<String?>(json['photoPath']),
      photoBlob: serializer.fromJson<String?>(json['photoBlob']),
      isFrozen: serializer.fromJson<bool>(json['isFrozen']),
      thawedDate: serializer.fromJson<DateTime?>(json['thawedDate']),
      emptiedAt: serializer.fromJson<DateTime?>(json['emptiedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      deleted: serializer.fromJson<bool>(json['deleted']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'syncId': serializer.toJson<String>(syncId),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deviceId': serializer.toJson<String?>(deviceId),
      'syncState': serializer.toJson<String>(syncState),
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'roaster': serializer.toJson<String?>(roaster),
      'roastDate': serializer.toJson<DateTime?>(roastDate),
      'isBlend': serializer.toJson<bool?>(isBlend),
      'roastedFor': serializer.toJson<String?>(roastedFor),
      'roastLevel': serializer.toJson<String?>(roastLevel),
      'country': serializer.toJson<String?>(country),
      'processing': serializer.toJson<String?>(processing),
      'variety': serializer.toJson<String?>(variety),
      'producer': serializer.toJson<String?>(producer),
      'weightGrams': serializer.toJson<double?>(weightGrams),
      'taste': serializer.toJson<String?>(taste),
      'cost': serializer.toJson<double?>(cost),
      'photoPath': serializer.toJson<String?>(photoPath),
      'photoBlob': serializer.toJson<String?>(photoBlob),
      'isFrozen': serializer.toJson<bool>(isFrozen),
      'thawedDate': serializer.toJson<DateTime?>(thawedDate),
      'emptiedAt': serializer.toJson<DateTime?>(emptiedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'deleted': serializer.toJson<bool>(deleted),
    };
  }

  Bean copyWith({
    String? syncId,
    int? updatedAt,
    Value<String?> deviceId = const Value.absent(),
    String? syncState,
    int? id,
    String? name,
    Value<String?> roaster = const Value.absent(),
    Value<DateTime?> roastDate = const Value.absent(),
    Value<bool?> isBlend = const Value.absent(),
    Value<String?> roastedFor = const Value.absent(),
    Value<String?> roastLevel = const Value.absent(),
    Value<String?> country = const Value.absent(),
    Value<String?> processing = const Value.absent(),
    Value<String?> variety = const Value.absent(),
    Value<String?> producer = const Value.absent(),
    Value<double?> weightGrams = const Value.absent(),
    Value<String?> taste = const Value.absent(),
    Value<double?> cost = const Value.absent(),
    Value<String?> photoPath = const Value.absent(),
    Value<String?> photoBlob = const Value.absent(),
    bool? isFrozen,
    Value<DateTime?> thawedDate = const Value.absent(),
    Value<DateTime?> emptiedAt = const Value.absent(),
    DateTime? createdAt,
    bool? deleted,
  }) => Bean(
    syncId: syncId ?? this.syncId,
    updatedAt: updatedAt ?? this.updatedAt,
    deviceId: deviceId.present ? deviceId.value : this.deviceId,
    syncState: syncState ?? this.syncState,
    id: id ?? this.id,
    name: name ?? this.name,
    roaster: roaster.present ? roaster.value : this.roaster,
    roastDate: roastDate.present ? roastDate.value : this.roastDate,
    isBlend: isBlend.present ? isBlend.value : this.isBlend,
    roastedFor: roastedFor.present ? roastedFor.value : this.roastedFor,
    roastLevel: roastLevel.present ? roastLevel.value : this.roastLevel,
    country: country.present ? country.value : this.country,
    processing: processing.present ? processing.value : this.processing,
    variety: variety.present ? variety.value : this.variety,
    producer: producer.present ? producer.value : this.producer,
    weightGrams: weightGrams.present ? weightGrams.value : this.weightGrams,
    taste: taste.present ? taste.value : this.taste,
    cost: cost.present ? cost.value : this.cost,
    photoPath: photoPath.present ? photoPath.value : this.photoPath,
    photoBlob: photoBlob.present ? photoBlob.value : this.photoBlob,
    isFrozen: isFrozen ?? this.isFrozen,
    thawedDate: thawedDate.present ? thawedDate.value : this.thawedDate,
    emptiedAt: emptiedAt.present ? emptiedAt.value : this.emptiedAt,
    createdAt: createdAt ?? this.createdAt,
    deleted: deleted ?? this.deleted,
  );
  Bean copyWithCompanion(BeansCompanion data) {
    return Bean(
      syncId: data.syncId.present ? data.syncId.value : this.syncId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      roaster: data.roaster.present ? data.roaster.value : this.roaster,
      roastDate: data.roastDate.present ? data.roastDate.value : this.roastDate,
      isBlend: data.isBlend.present ? data.isBlend.value : this.isBlend,
      roastedFor: data.roastedFor.present
          ? data.roastedFor.value
          : this.roastedFor,
      roastLevel: data.roastLevel.present
          ? data.roastLevel.value
          : this.roastLevel,
      country: data.country.present ? data.country.value : this.country,
      processing: data.processing.present
          ? data.processing.value
          : this.processing,
      variety: data.variety.present ? data.variety.value : this.variety,
      producer: data.producer.present ? data.producer.value : this.producer,
      weightGrams: data.weightGrams.present
          ? data.weightGrams.value
          : this.weightGrams,
      taste: data.taste.present ? data.taste.value : this.taste,
      cost: data.cost.present ? data.cost.value : this.cost,
      photoPath: data.photoPath.present ? data.photoPath.value : this.photoPath,
      photoBlob: data.photoBlob.present ? data.photoBlob.value : this.photoBlob,
      isFrozen: data.isFrozen.present ? data.isFrozen.value : this.isFrozen,
      thawedDate: data.thawedDate.present
          ? data.thawedDate.value
          : this.thawedDate,
      emptiedAt: data.emptiedAt.present ? data.emptiedAt.value : this.emptiedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Bean(')
          ..write('syncId: $syncId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deviceId: $deviceId, ')
          ..write('syncState: $syncState, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('roaster: $roaster, ')
          ..write('roastDate: $roastDate, ')
          ..write('isBlend: $isBlend, ')
          ..write('roastedFor: $roastedFor, ')
          ..write('roastLevel: $roastLevel, ')
          ..write('country: $country, ')
          ..write('processing: $processing, ')
          ..write('variety: $variety, ')
          ..write('producer: $producer, ')
          ..write('weightGrams: $weightGrams, ')
          ..write('taste: $taste, ')
          ..write('cost: $cost, ')
          ..write('photoPath: $photoPath, ')
          ..write('photoBlob: $photoBlob, ')
          ..write('isFrozen: $isFrozen, ')
          ..write('thawedDate: $thawedDate, ')
          ..write('emptiedAt: $emptiedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('deleted: $deleted')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    syncId,
    updatedAt,
    deviceId,
    syncState,
    id,
    name,
    roaster,
    roastDate,
    isBlend,
    roastedFor,
    roastLevel,
    country,
    processing,
    variety,
    producer,
    weightGrams,
    taste,
    cost,
    photoPath,
    photoBlob,
    isFrozen,
    thawedDate,
    emptiedAt,
    createdAt,
    deleted,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Bean &&
          other.syncId == this.syncId &&
          other.updatedAt == this.updatedAt &&
          other.deviceId == this.deviceId &&
          other.syncState == this.syncState &&
          other.id == this.id &&
          other.name == this.name &&
          other.roaster == this.roaster &&
          other.roastDate == this.roastDate &&
          other.isBlend == this.isBlend &&
          other.roastedFor == this.roastedFor &&
          other.roastLevel == this.roastLevel &&
          other.country == this.country &&
          other.processing == this.processing &&
          other.variety == this.variety &&
          other.producer == this.producer &&
          other.weightGrams == this.weightGrams &&
          other.taste == this.taste &&
          other.cost == this.cost &&
          other.photoPath == this.photoPath &&
          other.photoBlob == this.photoBlob &&
          other.isFrozen == this.isFrozen &&
          other.thawedDate == this.thawedDate &&
          other.emptiedAt == this.emptiedAt &&
          other.createdAt == this.createdAt &&
          other.deleted == this.deleted);
}

class BeansCompanion extends UpdateCompanion<Bean> {
  final Value<String> syncId;
  final Value<int> updatedAt;
  final Value<String?> deviceId;
  final Value<String> syncState;
  final Value<int> id;
  final Value<String> name;
  final Value<String?> roaster;
  final Value<DateTime?> roastDate;
  final Value<bool?> isBlend;
  final Value<String?> roastedFor;
  final Value<String?> roastLevel;
  final Value<String?> country;
  final Value<String?> processing;
  final Value<String?> variety;
  final Value<String?> producer;
  final Value<double?> weightGrams;
  final Value<String?> taste;
  final Value<double?> cost;
  final Value<String?> photoPath;
  final Value<String?> photoBlob;
  final Value<bool> isFrozen;
  final Value<DateTime?> thawedDate;
  final Value<DateTime?> emptiedAt;
  final Value<DateTime> createdAt;
  final Value<bool> deleted;
  const BeansCompanion({
    this.syncId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.syncState = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.roaster = const Value.absent(),
    this.roastDate = const Value.absent(),
    this.isBlend = const Value.absent(),
    this.roastedFor = const Value.absent(),
    this.roastLevel = const Value.absent(),
    this.country = const Value.absent(),
    this.processing = const Value.absent(),
    this.variety = const Value.absent(),
    this.producer = const Value.absent(),
    this.weightGrams = const Value.absent(),
    this.taste = const Value.absent(),
    this.cost = const Value.absent(),
    this.photoPath = const Value.absent(),
    this.photoBlob = const Value.absent(),
    this.isFrozen = const Value.absent(),
    this.thawedDate = const Value.absent(),
    this.emptiedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.deleted = const Value.absent(),
  });
  BeansCompanion.insert({
    this.syncId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.syncState = const Value.absent(),
    this.id = const Value.absent(),
    required String name,
    this.roaster = const Value.absent(),
    this.roastDate = const Value.absent(),
    this.isBlend = const Value.absent(),
    this.roastedFor = const Value.absent(),
    this.roastLevel = const Value.absent(),
    this.country = const Value.absent(),
    this.processing = const Value.absent(),
    this.variety = const Value.absent(),
    this.producer = const Value.absent(),
    this.weightGrams = const Value.absent(),
    this.taste = const Value.absent(),
    this.cost = const Value.absent(),
    this.photoPath = const Value.absent(),
    this.photoBlob = const Value.absent(),
    this.isFrozen = const Value.absent(),
    this.thawedDate = const Value.absent(),
    this.emptiedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.deleted = const Value.absent(),
  }) : name = Value(name);
  static Insertable<Bean> custom({
    Expression<String>? syncId,
    Expression<int>? updatedAt,
    Expression<String>? deviceId,
    Expression<String>? syncState,
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? roaster,
    Expression<DateTime>? roastDate,
    Expression<bool>? isBlend,
    Expression<String>? roastedFor,
    Expression<String>? roastLevel,
    Expression<String>? country,
    Expression<String>? processing,
    Expression<String>? variety,
    Expression<String>? producer,
    Expression<double>? weightGrams,
    Expression<String>? taste,
    Expression<double>? cost,
    Expression<String>? photoPath,
    Expression<String>? photoBlob,
    Expression<bool>? isFrozen,
    Expression<DateTime>? thawedDate,
    Expression<DateTime>? emptiedAt,
    Expression<DateTime>? createdAt,
    Expression<bool>? deleted,
  }) {
    return RawValuesInsertable({
      if (syncId != null) 'sync_id': syncId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deviceId != null) 'device_id': deviceId,
      if (syncState != null) 'sync_state': syncState,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (roaster != null) 'roaster': roaster,
      if (roastDate != null) 'roast_date': roastDate,
      if (isBlend != null) 'is_blend': isBlend,
      if (roastedFor != null) 'roasted_for': roastedFor,
      if (roastLevel != null) 'roast_level': roastLevel,
      if (country != null) 'country': country,
      if (processing != null) 'processing': processing,
      if (variety != null) 'variety': variety,
      if (producer != null) 'producer': producer,
      if (weightGrams != null) 'weight_grams': weightGrams,
      if (taste != null) 'taste': taste,
      if (cost != null) 'cost': cost,
      if (photoPath != null) 'photo_path': photoPath,
      if (photoBlob != null) 'photo_blob': photoBlob,
      if (isFrozen != null) 'is_frozen': isFrozen,
      if (thawedDate != null) 'thawed_date': thawedDate,
      if (emptiedAt != null) 'emptied_at': emptiedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (deleted != null) 'deleted': deleted,
    });
  }

  BeansCompanion copyWith({
    Value<String>? syncId,
    Value<int>? updatedAt,
    Value<String?>? deviceId,
    Value<String>? syncState,
    Value<int>? id,
    Value<String>? name,
    Value<String?>? roaster,
    Value<DateTime?>? roastDate,
    Value<bool?>? isBlend,
    Value<String?>? roastedFor,
    Value<String?>? roastLevel,
    Value<String?>? country,
    Value<String?>? processing,
    Value<String?>? variety,
    Value<String?>? producer,
    Value<double?>? weightGrams,
    Value<String?>? taste,
    Value<double?>? cost,
    Value<String?>? photoPath,
    Value<String?>? photoBlob,
    Value<bool>? isFrozen,
    Value<DateTime?>? thawedDate,
    Value<DateTime?>? emptiedAt,
    Value<DateTime>? createdAt,
    Value<bool>? deleted,
  }) {
    return BeansCompanion(
      syncId: syncId ?? this.syncId,
      updatedAt: updatedAt ?? this.updatedAt,
      deviceId: deviceId ?? this.deviceId,
      syncState: syncState ?? this.syncState,
      id: id ?? this.id,
      name: name ?? this.name,
      roaster: roaster ?? this.roaster,
      roastDate: roastDate ?? this.roastDate,
      isBlend: isBlend ?? this.isBlend,
      roastedFor: roastedFor ?? this.roastedFor,
      roastLevel: roastLevel ?? this.roastLevel,
      country: country ?? this.country,
      processing: processing ?? this.processing,
      variety: variety ?? this.variety,
      producer: producer ?? this.producer,
      weightGrams: weightGrams ?? this.weightGrams,
      taste: taste ?? this.taste,
      cost: cost ?? this.cost,
      photoPath: photoPath ?? this.photoPath,
      photoBlob: photoBlob ?? this.photoBlob,
      isFrozen: isFrozen ?? this.isFrozen,
      thawedDate: thawedDate ?? this.thawedDate,
      emptiedAt: emptiedAt ?? this.emptiedAt,
      createdAt: createdAt ?? this.createdAt,
      deleted: deleted ?? this.deleted,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (syncId.present) {
      map['sync_id'] = Variable<String>(syncId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<String>(syncState.value);
    }
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (roaster.present) {
      map['roaster'] = Variable<String>(roaster.value);
    }
    if (roastDate.present) {
      map['roast_date'] = Variable<DateTime>(roastDate.value);
    }
    if (isBlend.present) {
      map['is_blend'] = Variable<bool>(isBlend.value);
    }
    if (roastedFor.present) {
      map['roasted_for'] = Variable<String>(roastedFor.value);
    }
    if (roastLevel.present) {
      map['roast_level'] = Variable<String>(roastLevel.value);
    }
    if (country.present) {
      map['country'] = Variable<String>(country.value);
    }
    if (processing.present) {
      map['processing'] = Variable<String>(processing.value);
    }
    if (variety.present) {
      map['variety'] = Variable<String>(variety.value);
    }
    if (producer.present) {
      map['producer'] = Variable<String>(producer.value);
    }
    if (weightGrams.present) {
      map['weight_grams'] = Variable<double>(weightGrams.value);
    }
    if (taste.present) {
      map['taste'] = Variable<String>(taste.value);
    }
    if (cost.present) {
      map['cost'] = Variable<double>(cost.value);
    }
    if (photoPath.present) {
      map['photo_path'] = Variable<String>(photoPath.value);
    }
    if (photoBlob.present) {
      map['photo_blob'] = Variable<String>(photoBlob.value);
    }
    if (isFrozen.present) {
      map['is_frozen'] = Variable<bool>(isFrozen.value);
    }
    if (thawedDate.present) {
      map['thawed_date'] = Variable<DateTime>(thawedDate.value);
    }
    if (emptiedAt.present) {
      map['emptied_at'] = Variable<DateTime>(emptiedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BeansCompanion(')
          ..write('syncId: $syncId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deviceId: $deviceId, ')
          ..write('syncState: $syncState, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('roaster: $roaster, ')
          ..write('roastDate: $roastDate, ')
          ..write('isBlend: $isBlend, ')
          ..write('roastedFor: $roastedFor, ')
          ..write('roastLevel: $roastLevel, ')
          ..write('country: $country, ')
          ..write('processing: $processing, ')
          ..write('variety: $variety, ')
          ..write('producer: $producer, ')
          ..write('weightGrams: $weightGrams, ')
          ..write('taste: $taste, ')
          ..write('cost: $cost, ')
          ..write('photoPath: $photoPath, ')
          ..write('photoBlob: $photoBlob, ')
          ..write('isFrozen: $isFrozen, ')
          ..write('thawedDate: $thawedDate, ')
          ..write('emptiedAt: $emptiedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('deleted: $deleted')
          ..write(')'))
        .toString();
  }
}

class $ShotsTable extends Shots with TableInfo<$ShotsTable, Shot> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ShotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _syncIdMeta = const VerificationMeta('syncId');
  @override
  late final GeneratedColumn<String> syncId = GeneratedColumn<String>(
    'sync_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
    clientDefault: newSyncId,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    clientDefault: () => clock.now().millisecondsSinceEpoch,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<String> syncState = GeneratedColumn<String>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(SyncState.pending),
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _beanIdMeta = const VerificationMeta('beanId');
  @override
  late final GeneratedColumn<int> beanId = GeneratedColumn<int>(
    'bean_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES beans (id)',
    ),
  );
  static const VerificationMeta _profileNameMeta = const VerificationMeta(
    'profileName',
  );
  @override
  late final GeneratedColumn<String> profileName = GeneratedColumn<String>(
    'profile_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _doseGramsMeta = const VerificationMeta(
    'doseGrams',
  );
  @override
  late final GeneratedColumn<double> doseGrams = GeneratedColumn<double>(
    'dose_grams',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _finalWeightMeta = const VerificationMeta(
    'finalWeight',
  );
  @override
  late final GeneratedColumn<double> finalWeight = GeneratedColumn<double>(
    'final_weight',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _grindSizeMeta = const VerificationMeta(
    'grindSize',
  );
  @override
  late final GeneratedColumn<String> grindSize = GeneratedColumn<String>(
    'grind_size',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _grinderMeta = const VerificationMeta(
    'grinder',
  );
  @override
  late final GeneratedColumn<String> grinder = GeneratedColumn<String>(
    'grinder',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _burrsMeta = const VerificationMeta('burrs');
  @override
  late final GeneratedColumn<String> burrs = GeneratedColumn<String>(
    'burrs',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _brewedWithMeta = const VerificationMeta(
    'brewedWith',
  );
  @override
  late final GeneratedColumn<String> brewedWith = GeneratedColumn<String>(
    'brewed_with',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _brewChainIdMeta = const VerificationMeta(
    'brewChainId',
  );
  @override
  late final GeneratedColumn<String> brewChainId = GeneratedColumn<String>(
    'brew_chain_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _grindZeroMeta = const VerificationMeta(
    'grindZero',
  );
  @override
  late final GeneratedColumn<double> grindZero = GeneratedColumn<double>(
    'grind_zero',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _grindMarkerMeta = const VerificationMeta(
    'grindMarker',
  );
  @override
  late final GeneratedColumn<String> grindMarker = GeneratedColumn<String>(
    'grind_marker',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  @override
  late final GeneratedColumn<int> rating = GeneratedColumn<int>(
    'rating',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tasteFinishMeta = const VerificationMeta(
    'tasteFinish',
  );
  @override
  late final GeneratedColumn<int> tasteFinish = GeneratedColumn<int>(
    'taste_finish',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tasteBodyMeta = const VerificationMeta(
    'tasteBody',
  );
  @override
  late final GeneratedColumn<int> tasteBody = GeneratedColumn<int>(
    'taste_body',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tasteAcidityMeta = const VerificationMeta(
    'tasteAcidity',
  );
  @override
  late final GeneratedColumn<int> tasteAcidity = GeneratedColumn<int>(
    'taste_acidity',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tasteSweetnessMeta = const VerificationMeta(
    'tasteSweetness',
  );
  @override
  late final GeneratedColumn<int> tasteSweetness = GeneratedColumn<int>(
    'taste_sweetness',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tasteHollowMeta = const VerificationMeta(
    'tasteHollow',
  );
  @override
  late final GeneratedColumn<int> tasteHollow = GeneratedColumn<int>(
    'taste_hollow',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tasteSaltyMeta = const VerificationMeta(
    'tasteSalty',
  );
  @override
  late final GeneratedColumn<int> tasteSalty = GeneratedColumn<int>(
    'taste_salty',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tasteAstringentMeta = const VerificationMeta(
    'tasteAstringent',
  );
  @override
  late final GeneratedColumn<int> tasteAstringent = GeneratedColumn<int>(
    'taste_astringent',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tasteBitterMeta = const VerificationMeta(
    'tasteBitter',
  );
  @override
  late final GeneratedColumn<int> tasteBitter = GeneratedColumn<int>(
    'taste_bitter',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tasteExtrasMeta = const VerificationMeta(
    'tasteExtras',
  );
  @override
  late final GeneratedColumn<String> tasteExtras = GeneratedColumn<String>(
    'taste_extras',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _shotPhotoPathMeta = const VerificationMeta(
    'shotPhotoPath',
  );
  @override
  late final GeneratedColumn<String> shotPhotoPath = GeneratedColumn<String>(
    'shot_photo_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rawDebugJsonMeta = const VerificationMeta(
    'rawDebugJson',
  );
  @override
  late final GeneratedColumn<String> rawDebugJson = GeneratedColumn<String>(
    'raw_debug_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _externalIdMeta = const VerificationMeta(
    'externalId',
  );
  @override
  late final GeneratedColumn<String> externalId = GeneratedColumn<String>(
    'external_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _machineMeta = const VerificationMeta(
    'machine',
  );
  @override
  late final GeneratedColumn<String> machine = GeneratedColumn<String>(
    'machine',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('meticulous'),
  );
  static const VerificationMeta _profileColorMeta = const VerificationMeta(
    'profileColor',
  );
  @override
  late final GeneratedColumn<String> profileColor = GeneratedColumn<String>(
    'profile_color',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _profileImagePathMeta = const VerificationMeta(
    'profileImagePath',
  );
  @override
  late final GeneratedColumn<String> profileImagePath = GeneratedColumn<String>(
    'profile_image_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _brewTempMeta = const VerificationMeta(
    'brewTemp',
  );
  @override
  late final GeneratedColumn<double> brewTemp = GeneratedColumn<double>(
    'brew_temp',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _profileTempMeta = const VerificationMeta(
    'profileTemp',
  );
  @override
  late final GeneratedColumn<double> profileTemp = GeneratedColumn<double>(
    'profile_temp',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _aiAnalysisMeta = const VerificationMeta(
    'aiAnalysis',
  );
  @override
  late final GeneratedColumn<String> aiAnalysis = GeneratedColumn<String>(
    'ai_analysis',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _profileJsonMeta = const VerificationMeta(
    'profileJson',
  );
  @override
  late final GeneratedColumn<String> profileJson = GeneratedColumn<String>(
    'profile_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stageExitsMeta = const VerificationMeta(
    'stageExits',
  );
  @override
  late final GeneratedColumn<String> stageExits = GeneratedColumn<String>(
    'stage_exits',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _aiAnalysisModelMeta = const VerificationMeta(
    'aiAnalysisModel',
  );
  @override
  late final GeneratedColumn<String> aiAnalysisModel = GeneratedColumn<String>(
    'ai_analysis_model',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _aiAnalysedAtMeta = const VerificationMeta(
    'aiAnalysedAt',
  );
  @override
  late final GeneratedColumn<DateTime> aiAnalysedAt = GeneratedColumn<DateTime>(
    'ai_analysed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    syncId,
    updatedAt,
    deviceId,
    syncState,
    id,
    timestamp,
    beanId,
    profileName,
    doseGrams,
    finalWeight,
    durationMs,
    grindSize,
    grinder,
    burrs,
    brewedWith,
    brewChainId,
    grindZero,
    grindMarker,
    rating,
    tasteFinish,
    tasteBody,
    tasteAcidity,
    tasteSweetness,
    tasteHollow,
    tasteSalty,
    tasteAstringent,
    tasteBitter,
    tasteExtras,
    notes,
    shotPhotoPath,
    rawDebugJson,
    createdAt,
    externalId,
    machine,
    profileColor,
    profileImagePath,
    brewTemp,
    profileTemp,
    deletedAt,
    aiAnalysis,
    profileJson,
    stageExits,
    aiAnalysisModel,
    aiAnalysedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'shots';
  @override
  VerificationContext validateIntegrity(
    Insertable<Shot> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('sync_id')) {
      context.handle(
        _syncIdMeta,
        syncId.isAcceptableOrUnknown(data['sync_id']!, _syncIdMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('bean_id')) {
      context.handle(
        _beanIdMeta,
        beanId.isAcceptableOrUnknown(data['bean_id']!, _beanIdMeta),
      );
    }
    if (data.containsKey('profile_name')) {
      context.handle(
        _profileNameMeta,
        profileName.isAcceptableOrUnknown(
          data['profile_name']!,
          _profileNameMeta,
        ),
      );
    }
    if (data.containsKey('dose_grams')) {
      context.handle(
        _doseGramsMeta,
        doseGrams.isAcceptableOrUnknown(data['dose_grams']!, _doseGramsMeta),
      );
    }
    if (data.containsKey('final_weight')) {
      context.handle(
        _finalWeightMeta,
        finalWeight.isAcceptableOrUnknown(
          data['final_weight']!,
          _finalWeightMeta,
        ),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('grind_size')) {
      context.handle(
        _grindSizeMeta,
        grindSize.isAcceptableOrUnknown(data['grind_size']!, _grindSizeMeta),
      );
    }
    if (data.containsKey('grinder')) {
      context.handle(
        _grinderMeta,
        grinder.isAcceptableOrUnknown(data['grinder']!, _grinderMeta),
      );
    }
    if (data.containsKey('burrs')) {
      context.handle(
        _burrsMeta,
        burrs.isAcceptableOrUnknown(data['burrs']!, _burrsMeta),
      );
    }
    if (data.containsKey('brewed_with')) {
      context.handle(
        _brewedWithMeta,
        brewedWith.isAcceptableOrUnknown(data['brewed_with']!, _brewedWithMeta),
      );
    }
    if (data.containsKey('brew_chain_id')) {
      context.handle(
        _brewChainIdMeta,
        brewChainId.isAcceptableOrUnknown(
          data['brew_chain_id']!,
          _brewChainIdMeta,
        ),
      );
    }
    if (data.containsKey('grind_zero')) {
      context.handle(
        _grindZeroMeta,
        grindZero.isAcceptableOrUnknown(data['grind_zero']!, _grindZeroMeta),
      );
    }
    if (data.containsKey('grind_marker')) {
      context.handle(
        _grindMarkerMeta,
        grindMarker.isAcceptableOrUnknown(
          data['grind_marker']!,
          _grindMarkerMeta,
        ),
      );
    }
    if (data.containsKey('rating')) {
      context.handle(
        _ratingMeta,
        rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta),
      );
    }
    if (data.containsKey('taste_finish')) {
      context.handle(
        _tasteFinishMeta,
        tasteFinish.isAcceptableOrUnknown(
          data['taste_finish']!,
          _tasteFinishMeta,
        ),
      );
    }
    if (data.containsKey('taste_body')) {
      context.handle(
        _tasteBodyMeta,
        tasteBody.isAcceptableOrUnknown(data['taste_body']!, _tasteBodyMeta),
      );
    }
    if (data.containsKey('taste_acidity')) {
      context.handle(
        _tasteAcidityMeta,
        tasteAcidity.isAcceptableOrUnknown(
          data['taste_acidity']!,
          _tasteAcidityMeta,
        ),
      );
    }
    if (data.containsKey('taste_sweetness')) {
      context.handle(
        _tasteSweetnessMeta,
        tasteSweetness.isAcceptableOrUnknown(
          data['taste_sweetness']!,
          _tasteSweetnessMeta,
        ),
      );
    }
    if (data.containsKey('taste_hollow')) {
      context.handle(
        _tasteHollowMeta,
        tasteHollow.isAcceptableOrUnknown(
          data['taste_hollow']!,
          _tasteHollowMeta,
        ),
      );
    }
    if (data.containsKey('taste_salty')) {
      context.handle(
        _tasteSaltyMeta,
        tasteSalty.isAcceptableOrUnknown(data['taste_salty']!, _tasteSaltyMeta),
      );
    }
    if (data.containsKey('taste_astringent')) {
      context.handle(
        _tasteAstringentMeta,
        tasteAstringent.isAcceptableOrUnknown(
          data['taste_astringent']!,
          _tasteAstringentMeta,
        ),
      );
    }
    if (data.containsKey('taste_bitter')) {
      context.handle(
        _tasteBitterMeta,
        tasteBitter.isAcceptableOrUnknown(
          data['taste_bitter']!,
          _tasteBitterMeta,
        ),
      );
    }
    if (data.containsKey('taste_extras')) {
      context.handle(
        _tasteExtrasMeta,
        tasteExtras.isAcceptableOrUnknown(
          data['taste_extras']!,
          _tasteExtrasMeta,
        ),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('shot_photo_path')) {
      context.handle(
        _shotPhotoPathMeta,
        shotPhotoPath.isAcceptableOrUnknown(
          data['shot_photo_path']!,
          _shotPhotoPathMeta,
        ),
      );
    }
    if (data.containsKey('raw_debug_json')) {
      context.handle(
        _rawDebugJsonMeta,
        rawDebugJson.isAcceptableOrUnknown(
          data['raw_debug_json']!,
          _rawDebugJsonMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('external_id')) {
      context.handle(
        _externalIdMeta,
        externalId.isAcceptableOrUnknown(data['external_id']!, _externalIdMeta),
      );
    }
    if (data.containsKey('machine')) {
      context.handle(
        _machineMeta,
        machine.isAcceptableOrUnknown(data['machine']!, _machineMeta),
      );
    }
    if (data.containsKey('profile_color')) {
      context.handle(
        _profileColorMeta,
        profileColor.isAcceptableOrUnknown(
          data['profile_color']!,
          _profileColorMeta,
        ),
      );
    }
    if (data.containsKey('profile_image_path')) {
      context.handle(
        _profileImagePathMeta,
        profileImagePath.isAcceptableOrUnknown(
          data['profile_image_path']!,
          _profileImagePathMeta,
        ),
      );
    }
    if (data.containsKey('brew_temp')) {
      context.handle(
        _brewTempMeta,
        brewTemp.isAcceptableOrUnknown(data['brew_temp']!, _brewTempMeta),
      );
    }
    if (data.containsKey('profile_temp')) {
      context.handle(
        _profileTempMeta,
        profileTemp.isAcceptableOrUnknown(
          data['profile_temp']!,
          _profileTempMeta,
        ),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('ai_analysis')) {
      context.handle(
        _aiAnalysisMeta,
        aiAnalysis.isAcceptableOrUnknown(data['ai_analysis']!, _aiAnalysisMeta),
      );
    }
    if (data.containsKey('profile_json')) {
      context.handle(
        _profileJsonMeta,
        profileJson.isAcceptableOrUnknown(
          data['profile_json']!,
          _profileJsonMeta,
        ),
      );
    }
    if (data.containsKey('stage_exits')) {
      context.handle(
        _stageExitsMeta,
        stageExits.isAcceptableOrUnknown(data['stage_exits']!, _stageExitsMeta),
      );
    }
    if (data.containsKey('ai_analysis_model')) {
      context.handle(
        _aiAnalysisModelMeta,
        aiAnalysisModel.isAcceptableOrUnknown(
          data['ai_analysis_model']!,
          _aiAnalysisModelMeta,
        ),
      );
    }
    if (data.containsKey('ai_analysed_at')) {
      context.handle(
        _aiAnalysedAtMeta,
        aiAnalysedAt.isAcceptableOrUnknown(
          data['ai_analysed_at']!,
          _aiAnalysedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Shot map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Shot(
      syncId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      ),
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_state'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
      beanId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bean_id'],
      ),
      profileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_name'],
      ),
      doseGrams: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}dose_grams'],
      ),
      finalWeight: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}final_weight'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      grindSize: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}grind_size'],
      ),
      grinder: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}grinder'],
      ),
      burrs: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}burrs'],
      ),
      brewedWith: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}brewed_with'],
      ),
      brewChainId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}brew_chain_id'],
      ),
      grindZero: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}grind_zero'],
      ),
      grindMarker: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}grind_marker'],
      ),
      rating: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rating'],
      ),
      tasteFinish: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}taste_finish'],
      ),
      tasteBody: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}taste_body'],
      ),
      tasteAcidity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}taste_acidity'],
      ),
      tasteSweetness: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}taste_sweetness'],
      ),
      tasteHollow: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}taste_hollow'],
      ),
      tasteSalty: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}taste_salty'],
      ),
      tasteAstringent: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}taste_astringent'],
      ),
      tasteBitter: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}taste_bitter'],
      ),
      tasteExtras: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}taste_extras'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      shotPhotoPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shot_photo_path'],
      ),
      rawDebugJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_debug_json'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      externalId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}external_id'],
      ),
      machine: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}machine'],
      )!,
      profileColor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_color'],
      ),
      profileImagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_image_path'],
      ),
      brewTemp: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}brew_temp'],
      ),
      profileTemp: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}profile_temp'],
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      aiAnalysis: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ai_analysis'],
      ),
      profileJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_json'],
      ),
      stageExits: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stage_exits'],
      ),
      aiAnalysisModel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ai_analysis_model'],
      ),
      aiAnalysedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}ai_analysed_at'],
      ),
    );
  }

  @override
  $ShotsTable createAlias(String alias) {
    return $ShotsTable(attachedDatabase, alias);
  }
}

class Shot extends DataClass implements Insertable<Shot> {
  final String syncId;
  final int updatedAt;
  final String? deviceId;
  final String syncState;
  final int id;
  final DateTime timestamp;
  final int? beanId;
  final String? profileName;
  final double? doseGrams;
  final double? finalWeight;
  final int? durationMs;
  final String? grindSize;
  final String? grinder;
  final String? burrs;
  final String? brewedWith;
  final String? brewChainId;
  final double? grindZero;
  final String? grindMarker;
  final int? rating;
  final int? tasteFinish;
  final int? tasteBody;
  final int? tasteAcidity;
  final int? tasteSweetness;
  final int? tasteHollow;
  final int? tasteSalty;
  final int? tasteAstringent;
  final int? tasteBitter;
  final String? tasteExtras;
  final String? notes;
  final String? shotPhotoPath;
  final String? rawDebugJson;
  final DateTime createdAt;
  final String? externalId;
  final String machine;
  final String? profileColor;
  final String? profileImagePath;
  final double? brewTemp;
  final double? profileTemp;
  final DateTime? deletedAt;
  final String? aiAnalysis;
  final String? profileJson;
  final String? stageExits;
  final String? aiAnalysisModel;
  final DateTime? aiAnalysedAt;
  const Shot({
    required this.syncId,
    required this.updatedAt,
    this.deviceId,
    required this.syncState,
    required this.id,
    required this.timestamp,
    this.beanId,
    this.profileName,
    this.doseGrams,
    this.finalWeight,
    this.durationMs,
    this.grindSize,
    this.grinder,
    this.burrs,
    this.brewedWith,
    this.brewChainId,
    this.grindZero,
    this.grindMarker,
    this.rating,
    this.tasteFinish,
    this.tasteBody,
    this.tasteAcidity,
    this.tasteSweetness,
    this.tasteHollow,
    this.tasteSalty,
    this.tasteAstringent,
    this.tasteBitter,
    this.tasteExtras,
    this.notes,
    this.shotPhotoPath,
    this.rawDebugJson,
    required this.createdAt,
    this.externalId,
    required this.machine,
    this.profileColor,
    this.profileImagePath,
    this.brewTemp,
    this.profileTemp,
    this.deletedAt,
    this.aiAnalysis,
    this.profileJson,
    this.stageExits,
    this.aiAnalysisModel,
    this.aiAnalysedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['sync_id'] = Variable<String>(syncId);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deviceId != null) {
      map['device_id'] = Variable<String>(deviceId);
    }
    map['sync_state'] = Variable<String>(syncState);
    map['id'] = Variable<int>(id);
    map['timestamp'] = Variable<DateTime>(timestamp);
    if (!nullToAbsent || beanId != null) {
      map['bean_id'] = Variable<int>(beanId);
    }
    if (!nullToAbsent || profileName != null) {
      map['profile_name'] = Variable<String>(profileName);
    }
    if (!nullToAbsent || doseGrams != null) {
      map['dose_grams'] = Variable<double>(doseGrams);
    }
    if (!nullToAbsent || finalWeight != null) {
      map['final_weight'] = Variable<double>(finalWeight);
    }
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    if (!nullToAbsent || grindSize != null) {
      map['grind_size'] = Variable<String>(grindSize);
    }
    if (!nullToAbsent || grinder != null) {
      map['grinder'] = Variable<String>(grinder);
    }
    if (!nullToAbsent || burrs != null) {
      map['burrs'] = Variable<String>(burrs);
    }
    if (!nullToAbsent || brewedWith != null) {
      map['brewed_with'] = Variable<String>(brewedWith);
    }
    if (!nullToAbsent || brewChainId != null) {
      map['brew_chain_id'] = Variable<String>(brewChainId);
    }
    if (!nullToAbsent || grindZero != null) {
      map['grind_zero'] = Variable<double>(grindZero);
    }
    if (!nullToAbsent || grindMarker != null) {
      map['grind_marker'] = Variable<String>(grindMarker);
    }
    if (!nullToAbsent || rating != null) {
      map['rating'] = Variable<int>(rating);
    }
    if (!nullToAbsent || tasteFinish != null) {
      map['taste_finish'] = Variable<int>(tasteFinish);
    }
    if (!nullToAbsent || tasteBody != null) {
      map['taste_body'] = Variable<int>(tasteBody);
    }
    if (!nullToAbsent || tasteAcidity != null) {
      map['taste_acidity'] = Variable<int>(tasteAcidity);
    }
    if (!nullToAbsent || tasteSweetness != null) {
      map['taste_sweetness'] = Variable<int>(tasteSweetness);
    }
    if (!nullToAbsent || tasteHollow != null) {
      map['taste_hollow'] = Variable<int>(tasteHollow);
    }
    if (!nullToAbsent || tasteSalty != null) {
      map['taste_salty'] = Variable<int>(tasteSalty);
    }
    if (!nullToAbsent || tasteAstringent != null) {
      map['taste_astringent'] = Variable<int>(tasteAstringent);
    }
    if (!nullToAbsent || tasteBitter != null) {
      map['taste_bitter'] = Variable<int>(tasteBitter);
    }
    if (!nullToAbsent || tasteExtras != null) {
      map['taste_extras'] = Variable<String>(tasteExtras);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || shotPhotoPath != null) {
      map['shot_photo_path'] = Variable<String>(shotPhotoPath);
    }
    if (!nullToAbsent || rawDebugJson != null) {
      map['raw_debug_json'] = Variable<String>(rawDebugJson);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || externalId != null) {
      map['external_id'] = Variable<String>(externalId);
    }
    map['machine'] = Variable<String>(machine);
    if (!nullToAbsent || profileColor != null) {
      map['profile_color'] = Variable<String>(profileColor);
    }
    if (!nullToAbsent || profileImagePath != null) {
      map['profile_image_path'] = Variable<String>(profileImagePath);
    }
    if (!nullToAbsent || brewTemp != null) {
      map['brew_temp'] = Variable<double>(brewTemp);
    }
    if (!nullToAbsent || profileTemp != null) {
      map['profile_temp'] = Variable<double>(profileTemp);
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    if (!nullToAbsent || aiAnalysis != null) {
      map['ai_analysis'] = Variable<String>(aiAnalysis);
    }
    if (!nullToAbsent || profileJson != null) {
      map['profile_json'] = Variable<String>(profileJson);
    }
    if (!nullToAbsent || stageExits != null) {
      map['stage_exits'] = Variable<String>(stageExits);
    }
    if (!nullToAbsent || aiAnalysisModel != null) {
      map['ai_analysis_model'] = Variable<String>(aiAnalysisModel);
    }
    if (!nullToAbsent || aiAnalysedAt != null) {
      map['ai_analysed_at'] = Variable<DateTime>(aiAnalysedAt);
    }
    return map;
  }

  ShotsCompanion toCompanion(bool nullToAbsent) {
    return ShotsCompanion(
      syncId: Value(syncId),
      updatedAt: Value(updatedAt),
      deviceId: deviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceId),
      syncState: Value(syncState),
      id: Value(id),
      timestamp: Value(timestamp),
      beanId: beanId == null && nullToAbsent
          ? const Value.absent()
          : Value(beanId),
      profileName: profileName == null && nullToAbsent
          ? const Value.absent()
          : Value(profileName),
      doseGrams: doseGrams == null && nullToAbsent
          ? const Value.absent()
          : Value(doseGrams),
      finalWeight: finalWeight == null && nullToAbsent
          ? const Value.absent()
          : Value(finalWeight),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      grindSize: grindSize == null && nullToAbsent
          ? const Value.absent()
          : Value(grindSize),
      grinder: grinder == null && nullToAbsent
          ? const Value.absent()
          : Value(grinder),
      burrs: burrs == null && nullToAbsent
          ? const Value.absent()
          : Value(burrs),
      brewedWith: brewedWith == null && nullToAbsent
          ? const Value.absent()
          : Value(brewedWith),
      brewChainId: brewChainId == null && nullToAbsent
          ? const Value.absent()
          : Value(brewChainId),
      grindZero: grindZero == null && nullToAbsent
          ? const Value.absent()
          : Value(grindZero),
      grindMarker: grindMarker == null && nullToAbsent
          ? const Value.absent()
          : Value(grindMarker),
      rating: rating == null && nullToAbsent
          ? const Value.absent()
          : Value(rating),
      tasteFinish: tasteFinish == null && nullToAbsent
          ? const Value.absent()
          : Value(tasteFinish),
      tasteBody: tasteBody == null && nullToAbsent
          ? const Value.absent()
          : Value(tasteBody),
      tasteAcidity: tasteAcidity == null && nullToAbsent
          ? const Value.absent()
          : Value(tasteAcidity),
      tasteSweetness: tasteSweetness == null && nullToAbsent
          ? const Value.absent()
          : Value(tasteSweetness),
      tasteHollow: tasteHollow == null && nullToAbsent
          ? const Value.absent()
          : Value(tasteHollow),
      tasteSalty: tasteSalty == null && nullToAbsent
          ? const Value.absent()
          : Value(tasteSalty),
      tasteAstringent: tasteAstringent == null && nullToAbsent
          ? const Value.absent()
          : Value(tasteAstringent),
      tasteBitter: tasteBitter == null && nullToAbsent
          ? const Value.absent()
          : Value(tasteBitter),
      tasteExtras: tasteExtras == null && nullToAbsent
          ? const Value.absent()
          : Value(tasteExtras),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      shotPhotoPath: shotPhotoPath == null && nullToAbsent
          ? const Value.absent()
          : Value(shotPhotoPath),
      rawDebugJson: rawDebugJson == null && nullToAbsent
          ? const Value.absent()
          : Value(rawDebugJson),
      createdAt: Value(createdAt),
      externalId: externalId == null && nullToAbsent
          ? const Value.absent()
          : Value(externalId),
      machine: Value(machine),
      profileColor: profileColor == null && nullToAbsent
          ? const Value.absent()
          : Value(profileColor),
      profileImagePath: profileImagePath == null && nullToAbsent
          ? const Value.absent()
          : Value(profileImagePath),
      brewTemp: brewTemp == null && nullToAbsent
          ? const Value.absent()
          : Value(brewTemp),
      profileTemp: profileTemp == null && nullToAbsent
          ? const Value.absent()
          : Value(profileTemp),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      aiAnalysis: aiAnalysis == null && nullToAbsent
          ? const Value.absent()
          : Value(aiAnalysis),
      profileJson: profileJson == null && nullToAbsent
          ? const Value.absent()
          : Value(profileJson),
      stageExits: stageExits == null && nullToAbsent
          ? const Value.absent()
          : Value(stageExits),
      aiAnalysisModel: aiAnalysisModel == null && nullToAbsent
          ? const Value.absent()
          : Value(aiAnalysisModel),
      aiAnalysedAt: aiAnalysedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(aiAnalysedAt),
    );
  }

  factory Shot.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Shot(
      syncId: serializer.fromJson<String>(json['syncId']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deviceId: serializer.fromJson<String?>(json['deviceId']),
      syncState: serializer.fromJson<String>(json['syncState']),
      id: serializer.fromJson<int>(json['id']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      beanId: serializer.fromJson<int?>(json['beanId']),
      profileName: serializer.fromJson<String?>(json['profileName']),
      doseGrams: serializer.fromJson<double?>(json['doseGrams']),
      finalWeight: serializer.fromJson<double?>(json['finalWeight']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      grindSize: serializer.fromJson<String?>(json['grindSize']),
      grinder: serializer.fromJson<String?>(json['grinder']),
      burrs: serializer.fromJson<String?>(json['burrs']),
      brewedWith: serializer.fromJson<String?>(json['brewedWith']),
      brewChainId: serializer.fromJson<String?>(json['brewChainId']),
      grindZero: serializer.fromJson<double?>(json['grindZero']),
      grindMarker: serializer.fromJson<String?>(json['grindMarker']),
      rating: serializer.fromJson<int?>(json['rating']),
      tasteFinish: serializer.fromJson<int?>(json['tasteFinish']),
      tasteBody: serializer.fromJson<int?>(json['tasteBody']),
      tasteAcidity: serializer.fromJson<int?>(json['tasteAcidity']),
      tasteSweetness: serializer.fromJson<int?>(json['tasteSweetness']),
      tasteHollow: serializer.fromJson<int?>(json['tasteHollow']),
      tasteSalty: serializer.fromJson<int?>(json['tasteSalty']),
      tasteAstringent: serializer.fromJson<int?>(json['tasteAstringent']),
      tasteBitter: serializer.fromJson<int?>(json['tasteBitter']),
      tasteExtras: serializer.fromJson<String?>(json['tasteExtras']),
      notes: serializer.fromJson<String?>(json['notes']),
      shotPhotoPath: serializer.fromJson<String?>(json['shotPhotoPath']),
      rawDebugJson: serializer.fromJson<String?>(json['rawDebugJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      externalId: serializer.fromJson<String?>(json['externalId']),
      machine: serializer.fromJson<String>(json['machine']),
      profileColor: serializer.fromJson<String?>(json['profileColor']),
      profileImagePath: serializer.fromJson<String?>(json['profileImagePath']),
      brewTemp: serializer.fromJson<double?>(json['brewTemp']),
      profileTemp: serializer.fromJson<double?>(json['profileTemp']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      aiAnalysis: serializer.fromJson<String?>(json['aiAnalysis']),
      profileJson: serializer.fromJson<String?>(json['profileJson']),
      stageExits: serializer.fromJson<String?>(json['stageExits']),
      aiAnalysisModel: serializer.fromJson<String?>(json['aiAnalysisModel']),
      aiAnalysedAt: serializer.fromJson<DateTime?>(json['aiAnalysedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'syncId': serializer.toJson<String>(syncId),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deviceId': serializer.toJson<String?>(deviceId),
      'syncState': serializer.toJson<String>(syncState),
      'id': serializer.toJson<int>(id),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'beanId': serializer.toJson<int?>(beanId),
      'profileName': serializer.toJson<String?>(profileName),
      'doseGrams': serializer.toJson<double?>(doseGrams),
      'finalWeight': serializer.toJson<double?>(finalWeight),
      'durationMs': serializer.toJson<int?>(durationMs),
      'grindSize': serializer.toJson<String?>(grindSize),
      'grinder': serializer.toJson<String?>(grinder),
      'burrs': serializer.toJson<String?>(burrs),
      'brewedWith': serializer.toJson<String?>(brewedWith),
      'brewChainId': serializer.toJson<String?>(brewChainId),
      'grindZero': serializer.toJson<double?>(grindZero),
      'grindMarker': serializer.toJson<String?>(grindMarker),
      'rating': serializer.toJson<int?>(rating),
      'tasteFinish': serializer.toJson<int?>(tasteFinish),
      'tasteBody': serializer.toJson<int?>(tasteBody),
      'tasteAcidity': serializer.toJson<int?>(tasteAcidity),
      'tasteSweetness': serializer.toJson<int?>(tasteSweetness),
      'tasteHollow': serializer.toJson<int?>(tasteHollow),
      'tasteSalty': serializer.toJson<int?>(tasteSalty),
      'tasteAstringent': serializer.toJson<int?>(tasteAstringent),
      'tasteBitter': serializer.toJson<int?>(tasteBitter),
      'tasteExtras': serializer.toJson<String?>(tasteExtras),
      'notes': serializer.toJson<String?>(notes),
      'shotPhotoPath': serializer.toJson<String?>(shotPhotoPath),
      'rawDebugJson': serializer.toJson<String?>(rawDebugJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'externalId': serializer.toJson<String?>(externalId),
      'machine': serializer.toJson<String>(machine),
      'profileColor': serializer.toJson<String?>(profileColor),
      'profileImagePath': serializer.toJson<String?>(profileImagePath),
      'brewTemp': serializer.toJson<double?>(brewTemp),
      'profileTemp': serializer.toJson<double?>(profileTemp),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'aiAnalysis': serializer.toJson<String?>(aiAnalysis),
      'profileJson': serializer.toJson<String?>(profileJson),
      'stageExits': serializer.toJson<String?>(stageExits),
      'aiAnalysisModel': serializer.toJson<String?>(aiAnalysisModel),
      'aiAnalysedAt': serializer.toJson<DateTime?>(aiAnalysedAt),
    };
  }

  Shot copyWith({
    String? syncId,
    int? updatedAt,
    Value<String?> deviceId = const Value.absent(),
    String? syncState,
    int? id,
    DateTime? timestamp,
    Value<int?> beanId = const Value.absent(),
    Value<String?> profileName = const Value.absent(),
    Value<double?> doseGrams = const Value.absent(),
    Value<double?> finalWeight = const Value.absent(),
    Value<int?> durationMs = const Value.absent(),
    Value<String?> grindSize = const Value.absent(),
    Value<String?> grinder = const Value.absent(),
    Value<String?> burrs = const Value.absent(),
    Value<String?> brewedWith = const Value.absent(),
    Value<String?> brewChainId = const Value.absent(),
    Value<double?> grindZero = const Value.absent(),
    Value<String?> grindMarker = const Value.absent(),
    Value<int?> rating = const Value.absent(),
    Value<int?> tasteFinish = const Value.absent(),
    Value<int?> tasteBody = const Value.absent(),
    Value<int?> tasteAcidity = const Value.absent(),
    Value<int?> tasteSweetness = const Value.absent(),
    Value<int?> tasteHollow = const Value.absent(),
    Value<int?> tasteSalty = const Value.absent(),
    Value<int?> tasteAstringent = const Value.absent(),
    Value<int?> tasteBitter = const Value.absent(),
    Value<String?> tasteExtras = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    Value<String?> shotPhotoPath = const Value.absent(),
    Value<String?> rawDebugJson = const Value.absent(),
    DateTime? createdAt,
    Value<String?> externalId = const Value.absent(),
    String? machine,
    Value<String?> profileColor = const Value.absent(),
    Value<String?> profileImagePath = const Value.absent(),
    Value<double?> brewTemp = const Value.absent(),
    Value<double?> profileTemp = const Value.absent(),
    Value<DateTime?> deletedAt = const Value.absent(),
    Value<String?> aiAnalysis = const Value.absent(),
    Value<String?> profileJson = const Value.absent(),
    Value<String?> stageExits = const Value.absent(),
    Value<String?> aiAnalysisModel = const Value.absent(),
    Value<DateTime?> aiAnalysedAt = const Value.absent(),
  }) => Shot(
    syncId: syncId ?? this.syncId,
    updatedAt: updatedAt ?? this.updatedAt,
    deviceId: deviceId.present ? deviceId.value : this.deviceId,
    syncState: syncState ?? this.syncState,
    id: id ?? this.id,
    timestamp: timestamp ?? this.timestamp,
    beanId: beanId.present ? beanId.value : this.beanId,
    profileName: profileName.present ? profileName.value : this.profileName,
    doseGrams: doseGrams.present ? doseGrams.value : this.doseGrams,
    finalWeight: finalWeight.present ? finalWeight.value : this.finalWeight,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    grindSize: grindSize.present ? grindSize.value : this.grindSize,
    grinder: grinder.present ? grinder.value : this.grinder,
    burrs: burrs.present ? burrs.value : this.burrs,
    brewedWith: brewedWith.present ? brewedWith.value : this.brewedWith,
    brewChainId: brewChainId.present ? brewChainId.value : this.brewChainId,
    grindZero: grindZero.present ? grindZero.value : this.grindZero,
    grindMarker: grindMarker.present ? grindMarker.value : this.grindMarker,
    rating: rating.present ? rating.value : this.rating,
    tasteFinish: tasteFinish.present ? tasteFinish.value : this.tasteFinish,
    tasteBody: tasteBody.present ? tasteBody.value : this.tasteBody,
    tasteAcidity: tasteAcidity.present ? tasteAcidity.value : this.tasteAcidity,
    tasteSweetness: tasteSweetness.present
        ? tasteSweetness.value
        : this.tasteSweetness,
    tasteHollow: tasteHollow.present ? tasteHollow.value : this.tasteHollow,
    tasteSalty: tasteSalty.present ? tasteSalty.value : this.tasteSalty,
    tasteAstringent: tasteAstringent.present
        ? tasteAstringent.value
        : this.tasteAstringent,
    tasteBitter: tasteBitter.present ? tasteBitter.value : this.tasteBitter,
    tasteExtras: tasteExtras.present ? tasteExtras.value : this.tasteExtras,
    notes: notes.present ? notes.value : this.notes,
    shotPhotoPath: shotPhotoPath.present
        ? shotPhotoPath.value
        : this.shotPhotoPath,
    rawDebugJson: rawDebugJson.present ? rawDebugJson.value : this.rawDebugJson,
    createdAt: createdAt ?? this.createdAt,
    externalId: externalId.present ? externalId.value : this.externalId,
    machine: machine ?? this.machine,
    profileColor: profileColor.present ? profileColor.value : this.profileColor,
    profileImagePath: profileImagePath.present
        ? profileImagePath.value
        : this.profileImagePath,
    brewTemp: brewTemp.present ? brewTemp.value : this.brewTemp,
    profileTemp: profileTemp.present ? profileTemp.value : this.profileTemp,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    aiAnalysis: aiAnalysis.present ? aiAnalysis.value : this.aiAnalysis,
    profileJson: profileJson.present ? profileJson.value : this.profileJson,
    stageExits: stageExits.present ? stageExits.value : this.stageExits,
    aiAnalysisModel: aiAnalysisModel.present
        ? aiAnalysisModel.value
        : this.aiAnalysisModel,
    aiAnalysedAt: aiAnalysedAt.present ? aiAnalysedAt.value : this.aiAnalysedAt,
  );
  Shot copyWithCompanion(ShotsCompanion data) {
    return Shot(
      syncId: data.syncId.present ? data.syncId.value : this.syncId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
      id: data.id.present ? data.id.value : this.id,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      beanId: data.beanId.present ? data.beanId.value : this.beanId,
      profileName: data.profileName.present
          ? data.profileName.value
          : this.profileName,
      doseGrams: data.doseGrams.present ? data.doseGrams.value : this.doseGrams,
      finalWeight: data.finalWeight.present
          ? data.finalWeight.value
          : this.finalWeight,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      grindSize: data.grindSize.present ? data.grindSize.value : this.grindSize,
      grinder: data.grinder.present ? data.grinder.value : this.grinder,
      burrs: data.burrs.present ? data.burrs.value : this.burrs,
      brewedWith: data.brewedWith.present
          ? data.brewedWith.value
          : this.brewedWith,
      brewChainId: data.brewChainId.present
          ? data.brewChainId.value
          : this.brewChainId,
      grindZero: data.grindZero.present ? data.grindZero.value : this.grindZero,
      grindMarker: data.grindMarker.present
          ? data.grindMarker.value
          : this.grindMarker,
      rating: data.rating.present ? data.rating.value : this.rating,
      tasteFinish: data.tasteFinish.present
          ? data.tasteFinish.value
          : this.tasteFinish,
      tasteBody: data.tasteBody.present ? data.tasteBody.value : this.tasteBody,
      tasteAcidity: data.tasteAcidity.present
          ? data.tasteAcidity.value
          : this.tasteAcidity,
      tasteSweetness: data.tasteSweetness.present
          ? data.tasteSweetness.value
          : this.tasteSweetness,
      tasteHollow: data.tasteHollow.present
          ? data.tasteHollow.value
          : this.tasteHollow,
      tasteSalty: data.tasteSalty.present
          ? data.tasteSalty.value
          : this.tasteSalty,
      tasteAstringent: data.tasteAstringent.present
          ? data.tasteAstringent.value
          : this.tasteAstringent,
      tasteBitter: data.tasteBitter.present
          ? data.tasteBitter.value
          : this.tasteBitter,
      tasteExtras: data.tasteExtras.present
          ? data.tasteExtras.value
          : this.tasteExtras,
      notes: data.notes.present ? data.notes.value : this.notes,
      shotPhotoPath: data.shotPhotoPath.present
          ? data.shotPhotoPath.value
          : this.shotPhotoPath,
      rawDebugJson: data.rawDebugJson.present
          ? data.rawDebugJson.value
          : this.rawDebugJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      externalId: data.externalId.present
          ? data.externalId.value
          : this.externalId,
      machine: data.machine.present ? data.machine.value : this.machine,
      profileColor: data.profileColor.present
          ? data.profileColor.value
          : this.profileColor,
      profileImagePath: data.profileImagePath.present
          ? data.profileImagePath.value
          : this.profileImagePath,
      brewTemp: data.brewTemp.present ? data.brewTemp.value : this.brewTemp,
      profileTemp: data.profileTemp.present
          ? data.profileTemp.value
          : this.profileTemp,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      aiAnalysis: data.aiAnalysis.present
          ? data.aiAnalysis.value
          : this.aiAnalysis,
      profileJson: data.profileJson.present
          ? data.profileJson.value
          : this.profileJson,
      stageExits: data.stageExits.present
          ? data.stageExits.value
          : this.stageExits,
      aiAnalysisModel: data.aiAnalysisModel.present
          ? data.aiAnalysisModel.value
          : this.aiAnalysisModel,
      aiAnalysedAt: data.aiAnalysedAt.present
          ? data.aiAnalysedAt.value
          : this.aiAnalysedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Shot(')
          ..write('syncId: $syncId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deviceId: $deviceId, ')
          ..write('syncState: $syncState, ')
          ..write('id: $id, ')
          ..write('timestamp: $timestamp, ')
          ..write('beanId: $beanId, ')
          ..write('profileName: $profileName, ')
          ..write('doseGrams: $doseGrams, ')
          ..write('finalWeight: $finalWeight, ')
          ..write('durationMs: $durationMs, ')
          ..write('grindSize: $grindSize, ')
          ..write('grinder: $grinder, ')
          ..write('burrs: $burrs, ')
          ..write('brewedWith: $brewedWith, ')
          ..write('brewChainId: $brewChainId, ')
          ..write('grindZero: $grindZero, ')
          ..write('grindMarker: $grindMarker, ')
          ..write('rating: $rating, ')
          ..write('tasteFinish: $tasteFinish, ')
          ..write('tasteBody: $tasteBody, ')
          ..write('tasteAcidity: $tasteAcidity, ')
          ..write('tasteSweetness: $tasteSweetness, ')
          ..write('tasteHollow: $tasteHollow, ')
          ..write('tasteSalty: $tasteSalty, ')
          ..write('tasteAstringent: $tasteAstringent, ')
          ..write('tasteBitter: $tasteBitter, ')
          ..write('tasteExtras: $tasteExtras, ')
          ..write('notes: $notes, ')
          ..write('shotPhotoPath: $shotPhotoPath, ')
          ..write('rawDebugJson: $rawDebugJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('externalId: $externalId, ')
          ..write('machine: $machine, ')
          ..write('profileColor: $profileColor, ')
          ..write('profileImagePath: $profileImagePath, ')
          ..write('brewTemp: $brewTemp, ')
          ..write('profileTemp: $profileTemp, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('aiAnalysis: $aiAnalysis, ')
          ..write('profileJson: $profileJson, ')
          ..write('stageExits: $stageExits, ')
          ..write('aiAnalysisModel: $aiAnalysisModel, ')
          ..write('aiAnalysedAt: $aiAnalysedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    syncId,
    updatedAt,
    deviceId,
    syncState,
    id,
    timestamp,
    beanId,
    profileName,
    doseGrams,
    finalWeight,
    durationMs,
    grindSize,
    grinder,
    burrs,
    brewedWith,
    brewChainId,
    grindZero,
    grindMarker,
    rating,
    tasteFinish,
    tasteBody,
    tasteAcidity,
    tasteSweetness,
    tasteHollow,
    tasteSalty,
    tasteAstringent,
    tasteBitter,
    tasteExtras,
    notes,
    shotPhotoPath,
    rawDebugJson,
    createdAt,
    externalId,
    machine,
    profileColor,
    profileImagePath,
    brewTemp,
    profileTemp,
    deletedAt,
    aiAnalysis,
    profileJson,
    stageExits,
    aiAnalysisModel,
    aiAnalysedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Shot &&
          other.syncId == this.syncId &&
          other.updatedAt == this.updatedAt &&
          other.deviceId == this.deviceId &&
          other.syncState == this.syncState &&
          other.id == this.id &&
          other.timestamp == this.timestamp &&
          other.beanId == this.beanId &&
          other.profileName == this.profileName &&
          other.doseGrams == this.doseGrams &&
          other.finalWeight == this.finalWeight &&
          other.durationMs == this.durationMs &&
          other.grindSize == this.grindSize &&
          other.grinder == this.grinder &&
          other.burrs == this.burrs &&
          other.brewedWith == this.brewedWith &&
          other.brewChainId == this.brewChainId &&
          other.grindZero == this.grindZero &&
          other.grindMarker == this.grindMarker &&
          other.rating == this.rating &&
          other.tasteFinish == this.tasteFinish &&
          other.tasteBody == this.tasteBody &&
          other.tasteAcidity == this.tasteAcidity &&
          other.tasteSweetness == this.tasteSweetness &&
          other.tasteHollow == this.tasteHollow &&
          other.tasteSalty == this.tasteSalty &&
          other.tasteAstringent == this.tasteAstringent &&
          other.tasteBitter == this.tasteBitter &&
          other.tasteExtras == this.tasteExtras &&
          other.notes == this.notes &&
          other.shotPhotoPath == this.shotPhotoPath &&
          other.rawDebugJson == this.rawDebugJson &&
          other.createdAt == this.createdAt &&
          other.externalId == this.externalId &&
          other.machine == this.machine &&
          other.profileColor == this.profileColor &&
          other.profileImagePath == this.profileImagePath &&
          other.brewTemp == this.brewTemp &&
          other.profileTemp == this.profileTemp &&
          other.deletedAt == this.deletedAt &&
          other.aiAnalysis == this.aiAnalysis &&
          other.profileJson == this.profileJson &&
          other.stageExits == this.stageExits &&
          other.aiAnalysisModel == this.aiAnalysisModel &&
          other.aiAnalysedAt == this.aiAnalysedAt);
}

class ShotsCompanion extends UpdateCompanion<Shot> {
  final Value<String> syncId;
  final Value<int> updatedAt;
  final Value<String?> deviceId;
  final Value<String> syncState;
  final Value<int> id;
  final Value<DateTime> timestamp;
  final Value<int?> beanId;
  final Value<String?> profileName;
  final Value<double?> doseGrams;
  final Value<double?> finalWeight;
  final Value<int?> durationMs;
  final Value<String?> grindSize;
  final Value<String?> grinder;
  final Value<String?> burrs;
  final Value<String?> brewedWith;
  final Value<String?> brewChainId;
  final Value<double?> grindZero;
  final Value<String?> grindMarker;
  final Value<int?> rating;
  final Value<int?> tasteFinish;
  final Value<int?> tasteBody;
  final Value<int?> tasteAcidity;
  final Value<int?> tasteSweetness;
  final Value<int?> tasteHollow;
  final Value<int?> tasteSalty;
  final Value<int?> tasteAstringent;
  final Value<int?> tasteBitter;
  final Value<String?> tasteExtras;
  final Value<String?> notes;
  final Value<String?> shotPhotoPath;
  final Value<String?> rawDebugJson;
  final Value<DateTime> createdAt;
  final Value<String?> externalId;
  final Value<String> machine;
  final Value<String?> profileColor;
  final Value<String?> profileImagePath;
  final Value<double?> brewTemp;
  final Value<double?> profileTemp;
  final Value<DateTime?> deletedAt;
  final Value<String?> aiAnalysis;
  final Value<String?> profileJson;
  final Value<String?> stageExits;
  final Value<String?> aiAnalysisModel;
  final Value<DateTime?> aiAnalysedAt;
  const ShotsCompanion({
    this.syncId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.syncState = const Value.absent(),
    this.id = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.beanId = const Value.absent(),
    this.profileName = const Value.absent(),
    this.doseGrams = const Value.absent(),
    this.finalWeight = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.grindSize = const Value.absent(),
    this.grinder = const Value.absent(),
    this.burrs = const Value.absent(),
    this.brewedWith = const Value.absent(),
    this.brewChainId = const Value.absent(),
    this.grindZero = const Value.absent(),
    this.grindMarker = const Value.absent(),
    this.rating = const Value.absent(),
    this.tasteFinish = const Value.absent(),
    this.tasteBody = const Value.absent(),
    this.tasteAcidity = const Value.absent(),
    this.tasteSweetness = const Value.absent(),
    this.tasteHollow = const Value.absent(),
    this.tasteSalty = const Value.absent(),
    this.tasteAstringent = const Value.absent(),
    this.tasteBitter = const Value.absent(),
    this.tasteExtras = const Value.absent(),
    this.notes = const Value.absent(),
    this.shotPhotoPath = const Value.absent(),
    this.rawDebugJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.externalId = const Value.absent(),
    this.machine = const Value.absent(),
    this.profileColor = const Value.absent(),
    this.profileImagePath = const Value.absent(),
    this.brewTemp = const Value.absent(),
    this.profileTemp = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.aiAnalysis = const Value.absent(),
    this.profileJson = const Value.absent(),
    this.stageExits = const Value.absent(),
    this.aiAnalysisModel = const Value.absent(),
    this.aiAnalysedAt = const Value.absent(),
  });
  ShotsCompanion.insert({
    this.syncId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.syncState = const Value.absent(),
    this.id = const Value.absent(),
    required DateTime timestamp,
    this.beanId = const Value.absent(),
    this.profileName = const Value.absent(),
    this.doseGrams = const Value.absent(),
    this.finalWeight = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.grindSize = const Value.absent(),
    this.grinder = const Value.absent(),
    this.burrs = const Value.absent(),
    this.brewedWith = const Value.absent(),
    this.brewChainId = const Value.absent(),
    this.grindZero = const Value.absent(),
    this.grindMarker = const Value.absent(),
    this.rating = const Value.absent(),
    this.tasteFinish = const Value.absent(),
    this.tasteBody = const Value.absent(),
    this.tasteAcidity = const Value.absent(),
    this.tasteSweetness = const Value.absent(),
    this.tasteHollow = const Value.absent(),
    this.tasteSalty = const Value.absent(),
    this.tasteAstringent = const Value.absent(),
    this.tasteBitter = const Value.absent(),
    this.tasteExtras = const Value.absent(),
    this.notes = const Value.absent(),
    this.shotPhotoPath = const Value.absent(),
    this.rawDebugJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.externalId = const Value.absent(),
    this.machine = const Value.absent(),
    this.profileColor = const Value.absent(),
    this.profileImagePath = const Value.absent(),
    this.brewTemp = const Value.absent(),
    this.profileTemp = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.aiAnalysis = const Value.absent(),
    this.profileJson = const Value.absent(),
    this.stageExits = const Value.absent(),
    this.aiAnalysisModel = const Value.absent(),
    this.aiAnalysedAt = const Value.absent(),
  }) : timestamp = Value(timestamp);
  static Insertable<Shot> custom({
    Expression<String>? syncId,
    Expression<int>? updatedAt,
    Expression<String>? deviceId,
    Expression<String>? syncState,
    Expression<int>? id,
    Expression<DateTime>? timestamp,
    Expression<int>? beanId,
    Expression<String>? profileName,
    Expression<double>? doseGrams,
    Expression<double>? finalWeight,
    Expression<int>? durationMs,
    Expression<String>? grindSize,
    Expression<String>? grinder,
    Expression<String>? burrs,
    Expression<String>? brewedWith,
    Expression<String>? brewChainId,
    Expression<double>? grindZero,
    Expression<String>? grindMarker,
    Expression<int>? rating,
    Expression<int>? tasteFinish,
    Expression<int>? tasteBody,
    Expression<int>? tasteAcidity,
    Expression<int>? tasteSweetness,
    Expression<int>? tasteHollow,
    Expression<int>? tasteSalty,
    Expression<int>? tasteAstringent,
    Expression<int>? tasteBitter,
    Expression<String>? tasteExtras,
    Expression<String>? notes,
    Expression<String>? shotPhotoPath,
    Expression<String>? rawDebugJson,
    Expression<DateTime>? createdAt,
    Expression<String>? externalId,
    Expression<String>? machine,
    Expression<String>? profileColor,
    Expression<String>? profileImagePath,
    Expression<double>? brewTemp,
    Expression<double>? profileTemp,
    Expression<DateTime>? deletedAt,
    Expression<String>? aiAnalysis,
    Expression<String>? profileJson,
    Expression<String>? stageExits,
    Expression<String>? aiAnalysisModel,
    Expression<DateTime>? aiAnalysedAt,
  }) {
    return RawValuesInsertable({
      if (syncId != null) 'sync_id': syncId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deviceId != null) 'device_id': deviceId,
      if (syncState != null) 'sync_state': syncState,
      if (id != null) 'id': id,
      if (timestamp != null) 'timestamp': timestamp,
      if (beanId != null) 'bean_id': beanId,
      if (profileName != null) 'profile_name': profileName,
      if (doseGrams != null) 'dose_grams': doseGrams,
      if (finalWeight != null) 'final_weight': finalWeight,
      if (durationMs != null) 'duration_ms': durationMs,
      if (grindSize != null) 'grind_size': grindSize,
      if (grinder != null) 'grinder': grinder,
      if (burrs != null) 'burrs': burrs,
      if (brewedWith != null) 'brewed_with': brewedWith,
      if (brewChainId != null) 'brew_chain_id': brewChainId,
      if (grindZero != null) 'grind_zero': grindZero,
      if (grindMarker != null) 'grind_marker': grindMarker,
      if (rating != null) 'rating': rating,
      if (tasteFinish != null) 'taste_finish': tasteFinish,
      if (tasteBody != null) 'taste_body': tasteBody,
      if (tasteAcidity != null) 'taste_acidity': tasteAcidity,
      if (tasteSweetness != null) 'taste_sweetness': tasteSweetness,
      if (tasteHollow != null) 'taste_hollow': tasteHollow,
      if (tasteSalty != null) 'taste_salty': tasteSalty,
      if (tasteAstringent != null) 'taste_astringent': tasteAstringent,
      if (tasteBitter != null) 'taste_bitter': tasteBitter,
      if (tasteExtras != null) 'taste_extras': tasteExtras,
      if (notes != null) 'notes': notes,
      if (shotPhotoPath != null) 'shot_photo_path': shotPhotoPath,
      if (rawDebugJson != null) 'raw_debug_json': rawDebugJson,
      if (createdAt != null) 'created_at': createdAt,
      if (externalId != null) 'external_id': externalId,
      if (machine != null) 'machine': machine,
      if (profileColor != null) 'profile_color': profileColor,
      if (profileImagePath != null) 'profile_image_path': profileImagePath,
      if (brewTemp != null) 'brew_temp': brewTemp,
      if (profileTemp != null) 'profile_temp': profileTemp,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (aiAnalysis != null) 'ai_analysis': aiAnalysis,
      if (profileJson != null) 'profile_json': profileJson,
      if (stageExits != null) 'stage_exits': stageExits,
      if (aiAnalysisModel != null) 'ai_analysis_model': aiAnalysisModel,
      if (aiAnalysedAt != null) 'ai_analysed_at': aiAnalysedAt,
    });
  }

  ShotsCompanion copyWith({
    Value<String>? syncId,
    Value<int>? updatedAt,
    Value<String?>? deviceId,
    Value<String>? syncState,
    Value<int>? id,
    Value<DateTime>? timestamp,
    Value<int?>? beanId,
    Value<String?>? profileName,
    Value<double?>? doseGrams,
    Value<double?>? finalWeight,
    Value<int?>? durationMs,
    Value<String?>? grindSize,
    Value<String?>? grinder,
    Value<String?>? burrs,
    Value<String?>? brewedWith,
    Value<String?>? brewChainId,
    Value<double?>? grindZero,
    Value<String?>? grindMarker,
    Value<int?>? rating,
    Value<int?>? tasteFinish,
    Value<int?>? tasteBody,
    Value<int?>? tasteAcidity,
    Value<int?>? tasteSweetness,
    Value<int?>? tasteHollow,
    Value<int?>? tasteSalty,
    Value<int?>? tasteAstringent,
    Value<int?>? tasteBitter,
    Value<String?>? tasteExtras,
    Value<String?>? notes,
    Value<String?>? shotPhotoPath,
    Value<String?>? rawDebugJson,
    Value<DateTime>? createdAt,
    Value<String?>? externalId,
    Value<String>? machine,
    Value<String?>? profileColor,
    Value<String?>? profileImagePath,
    Value<double?>? brewTemp,
    Value<double?>? profileTemp,
    Value<DateTime?>? deletedAt,
    Value<String?>? aiAnalysis,
    Value<String?>? profileJson,
    Value<String?>? stageExits,
    Value<String?>? aiAnalysisModel,
    Value<DateTime?>? aiAnalysedAt,
  }) {
    return ShotsCompanion(
      syncId: syncId ?? this.syncId,
      updatedAt: updatedAt ?? this.updatedAt,
      deviceId: deviceId ?? this.deviceId,
      syncState: syncState ?? this.syncState,
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      beanId: beanId ?? this.beanId,
      profileName: profileName ?? this.profileName,
      doseGrams: doseGrams ?? this.doseGrams,
      finalWeight: finalWeight ?? this.finalWeight,
      durationMs: durationMs ?? this.durationMs,
      grindSize: grindSize ?? this.grindSize,
      grinder: grinder ?? this.grinder,
      burrs: burrs ?? this.burrs,
      brewedWith: brewedWith ?? this.brewedWith,
      brewChainId: brewChainId ?? this.brewChainId,
      grindZero: grindZero ?? this.grindZero,
      grindMarker: grindMarker ?? this.grindMarker,
      rating: rating ?? this.rating,
      tasteFinish: tasteFinish ?? this.tasteFinish,
      tasteBody: tasteBody ?? this.tasteBody,
      tasteAcidity: tasteAcidity ?? this.tasteAcidity,
      tasteSweetness: tasteSweetness ?? this.tasteSweetness,
      tasteHollow: tasteHollow ?? this.tasteHollow,
      tasteSalty: tasteSalty ?? this.tasteSalty,
      tasteAstringent: tasteAstringent ?? this.tasteAstringent,
      tasteBitter: tasteBitter ?? this.tasteBitter,
      tasteExtras: tasteExtras ?? this.tasteExtras,
      notes: notes ?? this.notes,
      shotPhotoPath: shotPhotoPath ?? this.shotPhotoPath,
      rawDebugJson: rawDebugJson ?? this.rawDebugJson,
      createdAt: createdAt ?? this.createdAt,
      externalId: externalId ?? this.externalId,
      machine: machine ?? this.machine,
      profileColor: profileColor ?? this.profileColor,
      profileImagePath: profileImagePath ?? this.profileImagePath,
      brewTemp: brewTemp ?? this.brewTemp,
      profileTemp: profileTemp ?? this.profileTemp,
      deletedAt: deletedAt ?? this.deletedAt,
      aiAnalysis: aiAnalysis ?? this.aiAnalysis,
      profileJson: profileJson ?? this.profileJson,
      stageExits: stageExits ?? this.stageExits,
      aiAnalysisModel: aiAnalysisModel ?? this.aiAnalysisModel,
      aiAnalysedAt: aiAnalysedAt ?? this.aiAnalysedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (syncId.present) {
      map['sync_id'] = Variable<String>(syncId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<String>(syncState.value);
    }
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (beanId.present) {
      map['bean_id'] = Variable<int>(beanId.value);
    }
    if (profileName.present) {
      map['profile_name'] = Variable<String>(profileName.value);
    }
    if (doseGrams.present) {
      map['dose_grams'] = Variable<double>(doseGrams.value);
    }
    if (finalWeight.present) {
      map['final_weight'] = Variable<double>(finalWeight.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (grindSize.present) {
      map['grind_size'] = Variable<String>(grindSize.value);
    }
    if (grinder.present) {
      map['grinder'] = Variable<String>(grinder.value);
    }
    if (burrs.present) {
      map['burrs'] = Variable<String>(burrs.value);
    }
    if (brewedWith.present) {
      map['brewed_with'] = Variable<String>(brewedWith.value);
    }
    if (brewChainId.present) {
      map['brew_chain_id'] = Variable<String>(brewChainId.value);
    }
    if (grindZero.present) {
      map['grind_zero'] = Variable<double>(grindZero.value);
    }
    if (grindMarker.present) {
      map['grind_marker'] = Variable<String>(grindMarker.value);
    }
    if (rating.present) {
      map['rating'] = Variable<int>(rating.value);
    }
    if (tasteFinish.present) {
      map['taste_finish'] = Variable<int>(tasteFinish.value);
    }
    if (tasteBody.present) {
      map['taste_body'] = Variable<int>(tasteBody.value);
    }
    if (tasteAcidity.present) {
      map['taste_acidity'] = Variable<int>(tasteAcidity.value);
    }
    if (tasteSweetness.present) {
      map['taste_sweetness'] = Variable<int>(tasteSweetness.value);
    }
    if (tasteHollow.present) {
      map['taste_hollow'] = Variable<int>(tasteHollow.value);
    }
    if (tasteSalty.present) {
      map['taste_salty'] = Variable<int>(tasteSalty.value);
    }
    if (tasteAstringent.present) {
      map['taste_astringent'] = Variable<int>(tasteAstringent.value);
    }
    if (tasteBitter.present) {
      map['taste_bitter'] = Variable<int>(tasteBitter.value);
    }
    if (tasteExtras.present) {
      map['taste_extras'] = Variable<String>(tasteExtras.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (shotPhotoPath.present) {
      map['shot_photo_path'] = Variable<String>(shotPhotoPath.value);
    }
    if (rawDebugJson.present) {
      map['raw_debug_json'] = Variable<String>(rawDebugJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (externalId.present) {
      map['external_id'] = Variable<String>(externalId.value);
    }
    if (machine.present) {
      map['machine'] = Variable<String>(machine.value);
    }
    if (profileColor.present) {
      map['profile_color'] = Variable<String>(profileColor.value);
    }
    if (profileImagePath.present) {
      map['profile_image_path'] = Variable<String>(profileImagePath.value);
    }
    if (brewTemp.present) {
      map['brew_temp'] = Variable<double>(brewTemp.value);
    }
    if (profileTemp.present) {
      map['profile_temp'] = Variable<double>(profileTemp.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (aiAnalysis.present) {
      map['ai_analysis'] = Variable<String>(aiAnalysis.value);
    }
    if (profileJson.present) {
      map['profile_json'] = Variable<String>(profileJson.value);
    }
    if (stageExits.present) {
      map['stage_exits'] = Variable<String>(stageExits.value);
    }
    if (aiAnalysisModel.present) {
      map['ai_analysis_model'] = Variable<String>(aiAnalysisModel.value);
    }
    if (aiAnalysedAt.present) {
      map['ai_analysed_at'] = Variable<DateTime>(aiAnalysedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ShotsCompanion(')
          ..write('syncId: $syncId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deviceId: $deviceId, ')
          ..write('syncState: $syncState, ')
          ..write('id: $id, ')
          ..write('timestamp: $timestamp, ')
          ..write('beanId: $beanId, ')
          ..write('profileName: $profileName, ')
          ..write('doseGrams: $doseGrams, ')
          ..write('finalWeight: $finalWeight, ')
          ..write('durationMs: $durationMs, ')
          ..write('grindSize: $grindSize, ')
          ..write('grinder: $grinder, ')
          ..write('burrs: $burrs, ')
          ..write('brewedWith: $brewedWith, ')
          ..write('brewChainId: $brewChainId, ')
          ..write('grindZero: $grindZero, ')
          ..write('grindMarker: $grindMarker, ')
          ..write('rating: $rating, ')
          ..write('tasteFinish: $tasteFinish, ')
          ..write('tasteBody: $tasteBody, ')
          ..write('tasteAcidity: $tasteAcidity, ')
          ..write('tasteSweetness: $tasteSweetness, ')
          ..write('tasteHollow: $tasteHollow, ')
          ..write('tasteSalty: $tasteSalty, ')
          ..write('tasteAstringent: $tasteAstringent, ')
          ..write('tasteBitter: $tasteBitter, ')
          ..write('tasteExtras: $tasteExtras, ')
          ..write('notes: $notes, ')
          ..write('shotPhotoPath: $shotPhotoPath, ')
          ..write('rawDebugJson: $rawDebugJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('externalId: $externalId, ')
          ..write('machine: $machine, ')
          ..write('profileColor: $profileColor, ')
          ..write('profileImagePath: $profileImagePath, ')
          ..write('brewTemp: $brewTemp, ')
          ..write('profileTemp: $profileTemp, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('aiAnalysis: $aiAnalysis, ')
          ..write('profileJson: $profileJson, ')
          ..write('stageExits: $stageExits, ')
          ..write('aiAnalysisModel: $aiAnalysisModel, ')
          ..write('aiAnalysedAt: $aiAnalysedAt')
          ..write(')'))
        .toString();
  }
}

class $ShotReadingsTable extends ShotReadings
    with TableInfo<$ShotReadingsTable, ShotReading> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ShotReadingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _shotIdMeta = const VerificationMeta('shotId');
  @override
  late final GeneratedColumn<int> shotId = GeneratedColumn<int>(
    'shot_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES shots (id)',
    ),
  );
  static const VerificationMeta _timeMsMeta = const VerificationMeta('timeMs');
  @override
  late final GeneratedColumn<int> timeMs = GeneratedColumn<int>(
    'time_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _profileMsMeta = const VerificationMeta(
    'profileMs',
  );
  @override
  late final GeneratedColumn<int> profileMs = GeneratedColumn<int>(
    'profile_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pressureMeta = const VerificationMeta(
    'pressure',
  );
  @override
  late final GeneratedColumn<double> pressure = GeneratedColumn<double>(
    'pressure',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _flowMeta = const VerificationMeta('flow');
  @override
  late final GeneratedColumn<double> flow = GeneratedColumn<double>(
    'flow',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _weightMeta = const VerificationMeta('weight');
  @override
  late final GeneratedColumn<double> weight = GeneratedColumn<double>(
    'weight',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _gravimetricFlowMeta = const VerificationMeta(
    'gravimetricFlow',
  );
  @override
  late final GeneratedColumn<double> gravimetricFlow = GeneratedColumn<double>(
    'gravimetric_flow',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _externalTemp1Meta = const VerificationMeta(
    'externalTemp1',
  );
  @override
  late final GeneratedColumn<double> externalTemp1 = GeneratedColumn<double>(
    'external_temp1',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _externalTemp2Meta = const VerificationMeta(
    'externalTemp2',
  );
  @override
  late final GeneratedColumn<double> externalTemp2 = GeneratedColumn<double>(
    'external_temp2',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _barUpMeta = const VerificationMeta('barUp');
  @override
  late final GeneratedColumn<double> barUp = GeneratedColumn<double>(
    'bar_up',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _barMidUpMeta = const VerificationMeta(
    'barMidUp',
  );
  @override
  late final GeneratedColumn<double> barMidUp = GeneratedColumn<double>(
    'bar_mid_up',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _barMidDownMeta = const VerificationMeta(
    'barMidDown',
  );
  @override
  late final GeneratedColumn<double> barMidDown = GeneratedColumn<double>(
    'bar_mid_down',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _barDownMeta = const VerificationMeta(
    'barDown',
  );
  @override
  late final GeneratedColumn<double> barDown = GeneratedColumn<double>(
    'bar_down',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tubeTempMeta = const VerificationMeta(
    'tubeTemp',
  );
  @override
  late final GeneratedColumn<double> tubeTemp = GeneratedColumn<double>(
    'tube_temp',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _motorTempMeta = const VerificationMeta(
    'motorTemp',
  );
  @override
  late final GeneratedColumn<double> motorTemp = GeneratedColumn<double>(
    'motor_temp',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lamTempMeta = const VerificationMeta(
    'lamTemp',
  );
  @override
  late final GeneratedColumn<double> lamTemp = GeneratedColumn<double>(
    'lam_temp',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _motorPositionMeta = const VerificationMeta(
    'motorPosition',
  );
  @override
  late final GeneratedColumn<double> motorPosition = GeneratedColumn<double>(
    'motor_position',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _motorSpeedMeta = const VerificationMeta(
    'motorSpeed',
  );
  @override
  late final GeneratedColumn<double> motorSpeed = GeneratedColumn<double>(
    'motor_speed',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _motorPowerMeta = const VerificationMeta(
    'motorPower',
  );
  @override
  late final GeneratedColumn<double> motorPower = GeneratedColumn<double>(
    'motor_power',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _motorCurrentMeta = const VerificationMeta(
    'motorCurrent',
  );
  @override
  late final GeneratedColumn<double> motorCurrent = GeneratedColumn<double>(
    'motor_current',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bandheaterPowerMeta = const VerificationMeta(
    'bandheaterPower',
  );
  @override
  late final GeneratedColumn<double> bandheaterPower = GeneratedColumn<double>(
    'bandheater_power',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bandheaterCurrentMeta = const VerificationMeta(
    'bandheaterCurrent',
  );
  @override
  late final GeneratedColumn<double> bandheaterCurrent =
      GeneratedColumn<double>(
        'bandheater_current',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _pressureSensorRawMeta = const VerificationMeta(
    'pressureSensorRaw',
  );
  @override
  late final GeneratedColumn<double> pressureSensorRaw =
      GeneratedColumn<double>(
        'pressure_sensor_raw',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _waterStatusMeta = const VerificationMeta(
    'waterStatus',
  );
  @override
  late final GeneratedColumn<bool> waterStatus = GeneratedColumn<bool>(
    'water_status',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("water_status" IN (0, 1))',
    ),
  );
  static const VerificationMeta _weightPredictionMeta = const VerificationMeta(
    'weightPrediction',
  );
  @override
  late final GeneratedColumn<double> weightPrediction = GeneratedColumn<double>(
    'weight_prediction',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stageMeta = const VerificationMeta('stage');
  @override
  late final GeneratedColumn<String> stage = GeneratedColumn<String>(
    'stage',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    shotId,
    timeMs,
    profileMs,
    pressure,
    flow,
    weight,
    gravimetricFlow,
    externalTemp1,
    externalTemp2,
    barUp,
    barMidUp,
    barMidDown,
    barDown,
    tubeTemp,
    motorTemp,
    lamTemp,
    motorPosition,
    motorSpeed,
    motorPower,
    motorCurrent,
    bandheaterPower,
    bandheaterCurrent,
    pressureSensorRaw,
    waterStatus,
    weightPrediction,
    stage,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'shot_readings';
  @override
  VerificationContext validateIntegrity(
    Insertable<ShotReading> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('shot_id')) {
      context.handle(
        _shotIdMeta,
        shotId.isAcceptableOrUnknown(data['shot_id']!, _shotIdMeta),
      );
    } else if (isInserting) {
      context.missing(_shotIdMeta);
    }
    if (data.containsKey('time_ms')) {
      context.handle(
        _timeMsMeta,
        timeMs.isAcceptableOrUnknown(data['time_ms']!, _timeMsMeta),
      );
    } else if (isInserting) {
      context.missing(_timeMsMeta);
    }
    if (data.containsKey('profile_ms')) {
      context.handle(
        _profileMsMeta,
        profileMs.isAcceptableOrUnknown(data['profile_ms']!, _profileMsMeta),
      );
    }
    if (data.containsKey('pressure')) {
      context.handle(
        _pressureMeta,
        pressure.isAcceptableOrUnknown(data['pressure']!, _pressureMeta),
      );
    }
    if (data.containsKey('flow')) {
      context.handle(
        _flowMeta,
        flow.isAcceptableOrUnknown(data['flow']!, _flowMeta),
      );
    }
    if (data.containsKey('weight')) {
      context.handle(
        _weightMeta,
        weight.isAcceptableOrUnknown(data['weight']!, _weightMeta),
      );
    }
    if (data.containsKey('gravimetric_flow')) {
      context.handle(
        _gravimetricFlowMeta,
        gravimetricFlow.isAcceptableOrUnknown(
          data['gravimetric_flow']!,
          _gravimetricFlowMeta,
        ),
      );
    }
    if (data.containsKey('external_temp1')) {
      context.handle(
        _externalTemp1Meta,
        externalTemp1.isAcceptableOrUnknown(
          data['external_temp1']!,
          _externalTemp1Meta,
        ),
      );
    }
    if (data.containsKey('external_temp2')) {
      context.handle(
        _externalTemp2Meta,
        externalTemp2.isAcceptableOrUnknown(
          data['external_temp2']!,
          _externalTemp2Meta,
        ),
      );
    }
    if (data.containsKey('bar_up')) {
      context.handle(
        _barUpMeta,
        barUp.isAcceptableOrUnknown(data['bar_up']!, _barUpMeta),
      );
    }
    if (data.containsKey('bar_mid_up')) {
      context.handle(
        _barMidUpMeta,
        barMidUp.isAcceptableOrUnknown(data['bar_mid_up']!, _barMidUpMeta),
      );
    }
    if (data.containsKey('bar_mid_down')) {
      context.handle(
        _barMidDownMeta,
        barMidDown.isAcceptableOrUnknown(
          data['bar_mid_down']!,
          _barMidDownMeta,
        ),
      );
    }
    if (data.containsKey('bar_down')) {
      context.handle(
        _barDownMeta,
        barDown.isAcceptableOrUnknown(data['bar_down']!, _barDownMeta),
      );
    }
    if (data.containsKey('tube_temp')) {
      context.handle(
        _tubeTempMeta,
        tubeTemp.isAcceptableOrUnknown(data['tube_temp']!, _tubeTempMeta),
      );
    }
    if (data.containsKey('motor_temp')) {
      context.handle(
        _motorTempMeta,
        motorTemp.isAcceptableOrUnknown(data['motor_temp']!, _motorTempMeta),
      );
    }
    if (data.containsKey('lam_temp')) {
      context.handle(
        _lamTempMeta,
        lamTemp.isAcceptableOrUnknown(data['lam_temp']!, _lamTempMeta),
      );
    }
    if (data.containsKey('motor_position')) {
      context.handle(
        _motorPositionMeta,
        motorPosition.isAcceptableOrUnknown(
          data['motor_position']!,
          _motorPositionMeta,
        ),
      );
    }
    if (data.containsKey('motor_speed')) {
      context.handle(
        _motorSpeedMeta,
        motorSpeed.isAcceptableOrUnknown(data['motor_speed']!, _motorSpeedMeta),
      );
    }
    if (data.containsKey('motor_power')) {
      context.handle(
        _motorPowerMeta,
        motorPower.isAcceptableOrUnknown(data['motor_power']!, _motorPowerMeta),
      );
    }
    if (data.containsKey('motor_current')) {
      context.handle(
        _motorCurrentMeta,
        motorCurrent.isAcceptableOrUnknown(
          data['motor_current']!,
          _motorCurrentMeta,
        ),
      );
    }
    if (data.containsKey('bandheater_power')) {
      context.handle(
        _bandheaterPowerMeta,
        bandheaterPower.isAcceptableOrUnknown(
          data['bandheater_power']!,
          _bandheaterPowerMeta,
        ),
      );
    }
    if (data.containsKey('bandheater_current')) {
      context.handle(
        _bandheaterCurrentMeta,
        bandheaterCurrent.isAcceptableOrUnknown(
          data['bandheater_current']!,
          _bandheaterCurrentMeta,
        ),
      );
    }
    if (data.containsKey('pressure_sensor_raw')) {
      context.handle(
        _pressureSensorRawMeta,
        pressureSensorRaw.isAcceptableOrUnknown(
          data['pressure_sensor_raw']!,
          _pressureSensorRawMeta,
        ),
      );
    }
    if (data.containsKey('water_status')) {
      context.handle(
        _waterStatusMeta,
        waterStatus.isAcceptableOrUnknown(
          data['water_status']!,
          _waterStatusMeta,
        ),
      );
    }
    if (data.containsKey('weight_prediction')) {
      context.handle(
        _weightPredictionMeta,
        weightPrediction.isAcceptableOrUnknown(
          data['weight_prediction']!,
          _weightPredictionMeta,
        ),
      );
    }
    if (data.containsKey('stage')) {
      context.handle(
        _stageMeta,
        stage.isAcceptableOrUnknown(data['stage']!, _stageMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ShotReading map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ShotReading(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      shotId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}shot_id'],
      )!,
      timeMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}time_ms'],
      )!,
      profileMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}profile_ms'],
      ),
      pressure: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}pressure'],
      ),
      flow: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}flow'],
      ),
      weight: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}weight'],
      ),
      gravimetricFlow: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}gravimetric_flow'],
      ),
      externalTemp1: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}external_temp1'],
      ),
      externalTemp2: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}external_temp2'],
      ),
      barUp: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bar_up'],
      ),
      barMidUp: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bar_mid_up'],
      ),
      barMidDown: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bar_mid_down'],
      ),
      barDown: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bar_down'],
      ),
      tubeTemp: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}tube_temp'],
      ),
      motorTemp: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}motor_temp'],
      ),
      lamTemp: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lam_temp'],
      ),
      motorPosition: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}motor_position'],
      ),
      motorSpeed: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}motor_speed'],
      ),
      motorPower: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}motor_power'],
      ),
      motorCurrent: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}motor_current'],
      ),
      bandheaterPower: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bandheater_power'],
      ),
      bandheaterCurrent: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bandheater_current'],
      ),
      pressureSensorRaw: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}pressure_sensor_raw'],
      ),
      waterStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}water_status'],
      ),
      weightPrediction: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}weight_prediction'],
      ),
      stage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stage'],
      ),
    );
  }

  @override
  $ShotReadingsTable createAlias(String alias) {
    return $ShotReadingsTable(attachedDatabase, alias);
  }
}

class ShotReading extends DataClass implements Insertable<ShotReading> {
  final int id;
  final int shotId;
  final int timeMs;
  final int? profileMs;
  final double? pressure;
  final double? flow;
  final double? weight;
  final double? gravimetricFlow;
  final double? externalTemp1;
  final double? externalTemp2;
  final double? barUp;
  final double? barMidUp;
  final double? barMidDown;
  final double? barDown;
  final double? tubeTemp;
  final double? motorTemp;
  final double? lamTemp;
  final double? motorPosition;
  final double? motorSpeed;
  final double? motorPower;
  final double? motorCurrent;
  final double? bandheaterPower;
  final double? bandheaterCurrent;
  final double? pressureSensorRaw;
  final bool? waterStatus;
  final double? weightPrediction;
  final String? stage;
  const ShotReading({
    required this.id,
    required this.shotId,
    required this.timeMs,
    this.profileMs,
    this.pressure,
    this.flow,
    this.weight,
    this.gravimetricFlow,
    this.externalTemp1,
    this.externalTemp2,
    this.barUp,
    this.barMidUp,
    this.barMidDown,
    this.barDown,
    this.tubeTemp,
    this.motorTemp,
    this.lamTemp,
    this.motorPosition,
    this.motorSpeed,
    this.motorPower,
    this.motorCurrent,
    this.bandheaterPower,
    this.bandheaterCurrent,
    this.pressureSensorRaw,
    this.waterStatus,
    this.weightPrediction,
    this.stage,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['shot_id'] = Variable<int>(shotId);
    map['time_ms'] = Variable<int>(timeMs);
    if (!nullToAbsent || profileMs != null) {
      map['profile_ms'] = Variable<int>(profileMs);
    }
    if (!nullToAbsent || pressure != null) {
      map['pressure'] = Variable<double>(pressure);
    }
    if (!nullToAbsent || flow != null) {
      map['flow'] = Variable<double>(flow);
    }
    if (!nullToAbsent || weight != null) {
      map['weight'] = Variable<double>(weight);
    }
    if (!nullToAbsent || gravimetricFlow != null) {
      map['gravimetric_flow'] = Variable<double>(gravimetricFlow);
    }
    if (!nullToAbsent || externalTemp1 != null) {
      map['external_temp1'] = Variable<double>(externalTemp1);
    }
    if (!nullToAbsent || externalTemp2 != null) {
      map['external_temp2'] = Variable<double>(externalTemp2);
    }
    if (!nullToAbsent || barUp != null) {
      map['bar_up'] = Variable<double>(barUp);
    }
    if (!nullToAbsent || barMidUp != null) {
      map['bar_mid_up'] = Variable<double>(barMidUp);
    }
    if (!nullToAbsent || barMidDown != null) {
      map['bar_mid_down'] = Variable<double>(barMidDown);
    }
    if (!nullToAbsent || barDown != null) {
      map['bar_down'] = Variable<double>(barDown);
    }
    if (!nullToAbsent || tubeTemp != null) {
      map['tube_temp'] = Variable<double>(tubeTemp);
    }
    if (!nullToAbsent || motorTemp != null) {
      map['motor_temp'] = Variable<double>(motorTemp);
    }
    if (!nullToAbsent || lamTemp != null) {
      map['lam_temp'] = Variable<double>(lamTemp);
    }
    if (!nullToAbsent || motorPosition != null) {
      map['motor_position'] = Variable<double>(motorPosition);
    }
    if (!nullToAbsent || motorSpeed != null) {
      map['motor_speed'] = Variable<double>(motorSpeed);
    }
    if (!nullToAbsent || motorPower != null) {
      map['motor_power'] = Variable<double>(motorPower);
    }
    if (!nullToAbsent || motorCurrent != null) {
      map['motor_current'] = Variable<double>(motorCurrent);
    }
    if (!nullToAbsent || bandheaterPower != null) {
      map['bandheater_power'] = Variable<double>(bandheaterPower);
    }
    if (!nullToAbsent || bandheaterCurrent != null) {
      map['bandheater_current'] = Variable<double>(bandheaterCurrent);
    }
    if (!nullToAbsent || pressureSensorRaw != null) {
      map['pressure_sensor_raw'] = Variable<double>(pressureSensorRaw);
    }
    if (!nullToAbsent || waterStatus != null) {
      map['water_status'] = Variable<bool>(waterStatus);
    }
    if (!nullToAbsent || weightPrediction != null) {
      map['weight_prediction'] = Variable<double>(weightPrediction);
    }
    if (!nullToAbsent || stage != null) {
      map['stage'] = Variable<String>(stage);
    }
    return map;
  }

  ShotReadingsCompanion toCompanion(bool nullToAbsent) {
    return ShotReadingsCompanion(
      id: Value(id),
      shotId: Value(shotId),
      timeMs: Value(timeMs),
      profileMs: profileMs == null && nullToAbsent
          ? const Value.absent()
          : Value(profileMs),
      pressure: pressure == null && nullToAbsent
          ? const Value.absent()
          : Value(pressure),
      flow: flow == null && nullToAbsent ? const Value.absent() : Value(flow),
      weight: weight == null && nullToAbsent
          ? const Value.absent()
          : Value(weight),
      gravimetricFlow: gravimetricFlow == null && nullToAbsent
          ? const Value.absent()
          : Value(gravimetricFlow),
      externalTemp1: externalTemp1 == null && nullToAbsent
          ? const Value.absent()
          : Value(externalTemp1),
      externalTemp2: externalTemp2 == null && nullToAbsent
          ? const Value.absent()
          : Value(externalTemp2),
      barUp: barUp == null && nullToAbsent
          ? const Value.absent()
          : Value(barUp),
      barMidUp: barMidUp == null && nullToAbsent
          ? const Value.absent()
          : Value(barMidUp),
      barMidDown: barMidDown == null && nullToAbsent
          ? const Value.absent()
          : Value(barMidDown),
      barDown: barDown == null && nullToAbsent
          ? const Value.absent()
          : Value(barDown),
      tubeTemp: tubeTemp == null && nullToAbsent
          ? const Value.absent()
          : Value(tubeTemp),
      motorTemp: motorTemp == null && nullToAbsent
          ? const Value.absent()
          : Value(motorTemp),
      lamTemp: lamTemp == null && nullToAbsent
          ? const Value.absent()
          : Value(lamTemp),
      motorPosition: motorPosition == null && nullToAbsent
          ? const Value.absent()
          : Value(motorPosition),
      motorSpeed: motorSpeed == null && nullToAbsent
          ? const Value.absent()
          : Value(motorSpeed),
      motorPower: motorPower == null && nullToAbsent
          ? const Value.absent()
          : Value(motorPower),
      motorCurrent: motorCurrent == null && nullToAbsent
          ? const Value.absent()
          : Value(motorCurrent),
      bandheaterPower: bandheaterPower == null && nullToAbsent
          ? const Value.absent()
          : Value(bandheaterPower),
      bandheaterCurrent: bandheaterCurrent == null && nullToAbsent
          ? const Value.absent()
          : Value(bandheaterCurrent),
      pressureSensorRaw: pressureSensorRaw == null && nullToAbsent
          ? const Value.absent()
          : Value(pressureSensorRaw),
      waterStatus: waterStatus == null && nullToAbsent
          ? const Value.absent()
          : Value(waterStatus),
      weightPrediction: weightPrediction == null && nullToAbsent
          ? const Value.absent()
          : Value(weightPrediction),
      stage: stage == null && nullToAbsent
          ? const Value.absent()
          : Value(stage),
    );
  }

  factory ShotReading.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ShotReading(
      id: serializer.fromJson<int>(json['id']),
      shotId: serializer.fromJson<int>(json['shotId']),
      timeMs: serializer.fromJson<int>(json['timeMs']),
      profileMs: serializer.fromJson<int?>(json['profileMs']),
      pressure: serializer.fromJson<double?>(json['pressure']),
      flow: serializer.fromJson<double?>(json['flow']),
      weight: serializer.fromJson<double?>(json['weight']),
      gravimetricFlow: serializer.fromJson<double?>(json['gravimetricFlow']),
      externalTemp1: serializer.fromJson<double?>(json['externalTemp1']),
      externalTemp2: serializer.fromJson<double?>(json['externalTemp2']),
      barUp: serializer.fromJson<double?>(json['barUp']),
      barMidUp: serializer.fromJson<double?>(json['barMidUp']),
      barMidDown: serializer.fromJson<double?>(json['barMidDown']),
      barDown: serializer.fromJson<double?>(json['barDown']),
      tubeTemp: serializer.fromJson<double?>(json['tubeTemp']),
      motorTemp: serializer.fromJson<double?>(json['motorTemp']),
      lamTemp: serializer.fromJson<double?>(json['lamTemp']),
      motorPosition: serializer.fromJson<double?>(json['motorPosition']),
      motorSpeed: serializer.fromJson<double?>(json['motorSpeed']),
      motorPower: serializer.fromJson<double?>(json['motorPower']),
      motorCurrent: serializer.fromJson<double?>(json['motorCurrent']),
      bandheaterPower: serializer.fromJson<double?>(json['bandheaterPower']),
      bandheaterCurrent: serializer.fromJson<double?>(
        json['bandheaterCurrent'],
      ),
      pressureSensorRaw: serializer.fromJson<double?>(
        json['pressureSensorRaw'],
      ),
      waterStatus: serializer.fromJson<bool?>(json['waterStatus']),
      weightPrediction: serializer.fromJson<double?>(json['weightPrediction']),
      stage: serializer.fromJson<String?>(json['stage']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'shotId': serializer.toJson<int>(shotId),
      'timeMs': serializer.toJson<int>(timeMs),
      'profileMs': serializer.toJson<int?>(profileMs),
      'pressure': serializer.toJson<double?>(pressure),
      'flow': serializer.toJson<double?>(flow),
      'weight': serializer.toJson<double?>(weight),
      'gravimetricFlow': serializer.toJson<double?>(gravimetricFlow),
      'externalTemp1': serializer.toJson<double?>(externalTemp1),
      'externalTemp2': serializer.toJson<double?>(externalTemp2),
      'barUp': serializer.toJson<double?>(barUp),
      'barMidUp': serializer.toJson<double?>(barMidUp),
      'barMidDown': serializer.toJson<double?>(barMidDown),
      'barDown': serializer.toJson<double?>(barDown),
      'tubeTemp': serializer.toJson<double?>(tubeTemp),
      'motorTemp': serializer.toJson<double?>(motorTemp),
      'lamTemp': serializer.toJson<double?>(lamTemp),
      'motorPosition': serializer.toJson<double?>(motorPosition),
      'motorSpeed': serializer.toJson<double?>(motorSpeed),
      'motorPower': serializer.toJson<double?>(motorPower),
      'motorCurrent': serializer.toJson<double?>(motorCurrent),
      'bandheaterPower': serializer.toJson<double?>(bandheaterPower),
      'bandheaterCurrent': serializer.toJson<double?>(bandheaterCurrent),
      'pressureSensorRaw': serializer.toJson<double?>(pressureSensorRaw),
      'waterStatus': serializer.toJson<bool?>(waterStatus),
      'weightPrediction': serializer.toJson<double?>(weightPrediction),
      'stage': serializer.toJson<String?>(stage),
    };
  }

  ShotReading copyWith({
    int? id,
    int? shotId,
    int? timeMs,
    Value<int?> profileMs = const Value.absent(),
    Value<double?> pressure = const Value.absent(),
    Value<double?> flow = const Value.absent(),
    Value<double?> weight = const Value.absent(),
    Value<double?> gravimetricFlow = const Value.absent(),
    Value<double?> externalTemp1 = const Value.absent(),
    Value<double?> externalTemp2 = const Value.absent(),
    Value<double?> barUp = const Value.absent(),
    Value<double?> barMidUp = const Value.absent(),
    Value<double?> barMidDown = const Value.absent(),
    Value<double?> barDown = const Value.absent(),
    Value<double?> tubeTemp = const Value.absent(),
    Value<double?> motorTemp = const Value.absent(),
    Value<double?> lamTemp = const Value.absent(),
    Value<double?> motorPosition = const Value.absent(),
    Value<double?> motorSpeed = const Value.absent(),
    Value<double?> motorPower = const Value.absent(),
    Value<double?> motorCurrent = const Value.absent(),
    Value<double?> bandheaterPower = const Value.absent(),
    Value<double?> bandheaterCurrent = const Value.absent(),
    Value<double?> pressureSensorRaw = const Value.absent(),
    Value<bool?> waterStatus = const Value.absent(),
    Value<double?> weightPrediction = const Value.absent(),
    Value<String?> stage = const Value.absent(),
  }) => ShotReading(
    id: id ?? this.id,
    shotId: shotId ?? this.shotId,
    timeMs: timeMs ?? this.timeMs,
    profileMs: profileMs.present ? profileMs.value : this.profileMs,
    pressure: pressure.present ? pressure.value : this.pressure,
    flow: flow.present ? flow.value : this.flow,
    weight: weight.present ? weight.value : this.weight,
    gravimetricFlow: gravimetricFlow.present
        ? gravimetricFlow.value
        : this.gravimetricFlow,
    externalTemp1: externalTemp1.present
        ? externalTemp1.value
        : this.externalTemp1,
    externalTemp2: externalTemp2.present
        ? externalTemp2.value
        : this.externalTemp2,
    barUp: barUp.present ? barUp.value : this.barUp,
    barMidUp: barMidUp.present ? barMidUp.value : this.barMidUp,
    barMidDown: barMidDown.present ? barMidDown.value : this.barMidDown,
    barDown: barDown.present ? barDown.value : this.barDown,
    tubeTemp: tubeTemp.present ? tubeTemp.value : this.tubeTemp,
    motorTemp: motorTemp.present ? motorTemp.value : this.motorTemp,
    lamTemp: lamTemp.present ? lamTemp.value : this.lamTemp,
    motorPosition: motorPosition.present
        ? motorPosition.value
        : this.motorPosition,
    motorSpeed: motorSpeed.present ? motorSpeed.value : this.motorSpeed,
    motorPower: motorPower.present ? motorPower.value : this.motorPower,
    motorCurrent: motorCurrent.present ? motorCurrent.value : this.motorCurrent,
    bandheaterPower: bandheaterPower.present
        ? bandheaterPower.value
        : this.bandheaterPower,
    bandheaterCurrent: bandheaterCurrent.present
        ? bandheaterCurrent.value
        : this.bandheaterCurrent,
    pressureSensorRaw: pressureSensorRaw.present
        ? pressureSensorRaw.value
        : this.pressureSensorRaw,
    waterStatus: waterStatus.present ? waterStatus.value : this.waterStatus,
    weightPrediction: weightPrediction.present
        ? weightPrediction.value
        : this.weightPrediction,
    stage: stage.present ? stage.value : this.stage,
  );
  ShotReading copyWithCompanion(ShotReadingsCompanion data) {
    return ShotReading(
      id: data.id.present ? data.id.value : this.id,
      shotId: data.shotId.present ? data.shotId.value : this.shotId,
      timeMs: data.timeMs.present ? data.timeMs.value : this.timeMs,
      profileMs: data.profileMs.present ? data.profileMs.value : this.profileMs,
      pressure: data.pressure.present ? data.pressure.value : this.pressure,
      flow: data.flow.present ? data.flow.value : this.flow,
      weight: data.weight.present ? data.weight.value : this.weight,
      gravimetricFlow: data.gravimetricFlow.present
          ? data.gravimetricFlow.value
          : this.gravimetricFlow,
      externalTemp1: data.externalTemp1.present
          ? data.externalTemp1.value
          : this.externalTemp1,
      externalTemp2: data.externalTemp2.present
          ? data.externalTemp2.value
          : this.externalTemp2,
      barUp: data.barUp.present ? data.barUp.value : this.barUp,
      barMidUp: data.barMidUp.present ? data.barMidUp.value : this.barMidUp,
      barMidDown: data.barMidDown.present
          ? data.barMidDown.value
          : this.barMidDown,
      barDown: data.barDown.present ? data.barDown.value : this.barDown,
      tubeTemp: data.tubeTemp.present ? data.tubeTemp.value : this.tubeTemp,
      motorTemp: data.motorTemp.present ? data.motorTemp.value : this.motorTemp,
      lamTemp: data.lamTemp.present ? data.lamTemp.value : this.lamTemp,
      motorPosition: data.motorPosition.present
          ? data.motorPosition.value
          : this.motorPosition,
      motorSpeed: data.motorSpeed.present
          ? data.motorSpeed.value
          : this.motorSpeed,
      motorPower: data.motorPower.present
          ? data.motorPower.value
          : this.motorPower,
      motorCurrent: data.motorCurrent.present
          ? data.motorCurrent.value
          : this.motorCurrent,
      bandheaterPower: data.bandheaterPower.present
          ? data.bandheaterPower.value
          : this.bandheaterPower,
      bandheaterCurrent: data.bandheaterCurrent.present
          ? data.bandheaterCurrent.value
          : this.bandheaterCurrent,
      pressureSensorRaw: data.pressureSensorRaw.present
          ? data.pressureSensorRaw.value
          : this.pressureSensorRaw,
      waterStatus: data.waterStatus.present
          ? data.waterStatus.value
          : this.waterStatus,
      weightPrediction: data.weightPrediction.present
          ? data.weightPrediction.value
          : this.weightPrediction,
      stage: data.stage.present ? data.stage.value : this.stage,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ShotReading(')
          ..write('id: $id, ')
          ..write('shotId: $shotId, ')
          ..write('timeMs: $timeMs, ')
          ..write('profileMs: $profileMs, ')
          ..write('pressure: $pressure, ')
          ..write('flow: $flow, ')
          ..write('weight: $weight, ')
          ..write('gravimetricFlow: $gravimetricFlow, ')
          ..write('externalTemp1: $externalTemp1, ')
          ..write('externalTemp2: $externalTemp2, ')
          ..write('barUp: $barUp, ')
          ..write('barMidUp: $barMidUp, ')
          ..write('barMidDown: $barMidDown, ')
          ..write('barDown: $barDown, ')
          ..write('tubeTemp: $tubeTemp, ')
          ..write('motorTemp: $motorTemp, ')
          ..write('lamTemp: $lamTemp, ')
          ..write('motorPosition: $motorPosition, ')
          ..write('motorSpeed: $motorSpeed, ')
          ..write('motorPower: $motorPower, ')
          ..write('motorCurrent: $motorCurrent, ')
          ..write('bandheaterPower: $bandheaterPower, ')
          ..write('bandheaterCurrent: $bandheaterCurrent, ')
          ..write('pressureSensorRaw: $pressureSensorRaw, ')
          ..write('waterStatus: $waterStatus, ')
          ..write('weightPrediction: $weightPrediction, ')
          ..write('stage: $stage')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    shotId,
    timeMs,
    profileMs,
    pressure,
    flow,
    weight,
    gravimetricFlow,
    externalTemp1,
    externalTemp2,
    barUp,
    barMidUp,
    barMidDown,
    barDown,
    tubeTemp,
    motorTemp,
    lamTemp,
    motorPosition,
    motorSpeed,
    motorPower,
    motorCurrent,
    bandheaterPower,
    bandheaterCurrent,
    pressureSensorRaw,
    waterStatus,
    weightPrediction,
    stage,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ShotReading &&
          other.id == this.id &&
          other.shotId == this.shotId &&
          other.timeMs == this.timeMs &&
          other.profileMs == this.profileMs &&
          other.pressure == this.pressure &&
          other.flow == this.flow &&
          other.weight == this.weight &&
          other.gravimetricFlow == this.gravimetricFlow &&
          other.externalTemp1 == this.externalTemp1 &&
          other.externalTemp2 == this.externalTemp2 &&
          other.barUp == this.barUp &&
          other.barMidUp == this.barMidUp &&
          other.barMidDown == this.barMidDown &&
          other.barDown == this.barDown &&
          other.tubeTemp == this.tubeTemp &&
          other.motorTemp == this.motorTemp &&
          other.lamTemp == this.lamTemp &&
          other.motorPosition == this.motorPosition &&
          other.motorSpeed == this.motorSpeed &&
          other.motorPower == this.motorPower &&
          other.motorCurrent == this.motorCurrent &&
          other.bandheaterPower == this.bandheaterPower &&
          other.bandheaterCurrent == this.bandheaterCurrent &&
          other.pressureSensorRaw == this.pressureSensorRaw &&
          other.waterStatus == this.waterStatus &&
          other.weightPrediction == this.weightPrediction &&
          other.stage == this.stage);
}

class ShotReadingsCompanion extends UpdateCompanion<ShotReading> {
  final Value<int> id;
  final Value<int> shotId;
  final Value<int> timeMs;
  final Value<int?> profileMs;
  final Value<double?> pressure;
  final Value<double?> flow;
  final Value<double?> weight;
  final Value<double?> gravimetricFlow;
  final Value<double?> externalTemp1;
  final Value<double?> externalTemp2;
  final Value<double?> barUp;
  final Value<double?> barMidUp;
  final Value<double?> barMidDown;
  final Value<double?> barDown;
  final Value<double?> tubeTemp;
  final Value<double?> motorTemp;
  final Value<double?> lamTemp;
  final Value<double?> motorPosition;
  final Value<double?> motorSpeed;
  final Value<double?> motorPower;
  final Value<double?> motorCurrent;
  final Value<double?> bandheaterPower;
  final Value<double?> bandheaterCurrent;
  final Value<double?> pressureSensorRaw;
  final Value<bool?> waterStatus;
  final Value<double?> weightPrediction;
  final Value<String?> stage;
  const ShotReadingsCompanion({
    this.id = const Value.absent(),
    this.shotId = const Value.absent(),
    this.timeMs = const Value.absent(),
    this.profileMs = const Value.absent(),
    this.pressure = const Value.absent(),
    this.flow = const Value.absent(),
    this.weight = const Value.absent(),
    this.gravimetricFlow = const Value.absent(),
    this.externalTemp1 = const Value.absent(),
    this.externalTemp2 = const Value.absent(),
    this.barUp = const Value.absent(),
    this.barMidUp = const Value.absent(),
    this.barMidDown = const Value.absent(),
    this.barDown = const Value.absent(),
    this.tubeTemp = const Value.absent(),
    this.motorTemp = const Value.absent(),
    this.lamTemp = const Value.absent(),
    this.motorPosition = const Value.absent(),
    this.motorSpeed = const Value.absent(),
    this.motorPower = const Value.absent(),
    this.motorCurrent = const Value.absent(),
    this.bandheaterPower = const Value.absent(),
    this.bandheaterCurrent = const Value.absent(),
    this.pressureSensorRaw = const Value.absent(),
    this.waterStatus = const Value.absent(),
    this.weightPrediction = const Value.absent(),
    this.stage = const Value.absent(),
  });
  ShotReadingsCompanion.insert({
    this.id = const Value.absent(),
    required int shotId,
    required int timeMs,
    this.profileMs = const Value.absent(),
    this.pressure = const Value.absent(),
    this.flow = const Value.absent(),
    this.weight = const Value.absent(),
    this.gravimetricFlow = const Value.absent(),
    this.externalTemp1 = const Value.absent(),
    this.externalTemp2 = const Value.absent(),
    this.barUp = const Value.absent(),
    this.barMidUp = const Value.absent(),
    this.barMidDown = const Value.absent(),
    this.barDown = const Value.absent(),
    this.tubeTemp = const Value.absent(),
    this.motorTemp = const Value.absent(),
    this.lamTemp = const Value.absent(),
    this.motorPosition = const Value.absent(),
    this.motorSpeed = const Value.absent(),
    this.motorPower = const Value.absent(),
    this.motorCurrent = const Value.absent(),
    this.bandheaterPower = const Value.absent(),
    this.bandheaterCurrent = const Value.absent(),
    this.pressureSensorRaw = const Value.absent(),
    this.waterStatus = const Value.absent(),
    this.weightPrediction = const Value.absent(),
    this.stage = const Value.absent(),
  }) : shotId = Value(shotId),
       timeMs = Value(timeMs);
  static Insertable<ShotReading> custom({
    Expression<int>? id,
    Expression<int>? shotId,
    Expression<int>? timeMs,
    Expression<int>? profileMs,
    Expression<double>? pressure,
    Expression<double>? flow,
    Expression<double>? weight,
    Expression<double>? gravimetricFlow,
    Expression<double>? externalTemp1,
    Expression<double>? externalTemp2,
    Expression<double>? barUp,
    Expression<double>? barMidUp,
    Expression<double>? barMidDown,
    Expression<double>? barDown,
    Expression<double>? tubeTemp,
    Expression<double>? motorTemp,
    Expression<double>? lamTemp,
    Expression<double>? motorPosition,
    Expression<double>? motorSpeed,
    Expression<double>? motorPower,
    Expression<double>? motorCurrent,
    Expression<double>? bandheaterPower,
    Expression<double>? bandheaterCurrent,
    Expression<double>? pressureSensorRaw,
    Expression<bool>? waterStatus,
    Expression<double>? weightPrediction,
    Expression<String>? stage,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (shotId != null) 'shot_id': shotId,
      if (timeMs != null) 'time_ms': timeMs,
      if (profileMs != null) 'profile_ms': profileMs,
      if (pressure != null) 'pressure': pressure,
      if (flow != null) 'flow': flow,
      if (weight != null) 'weight': weight,
      if (gravimetricFlow != null) 'gravimetric_flow': gravimetricFlow,
      if (externalTemp1 != null) 'external_temp1': externalTemp1,
      if (externalTemp2 != null) 'external_temp2': externalTemp2,
      if (barUp != null) 'bar_up': barUp,
      if (barMidUp != null) 'bar_mid_up': barMidUp,
      if (barMidDown != null) 'bar_mid_down': barMidDown,
      if (barDown != null) 'bar_down': barDown,
      if (tubeTemp != null) 'tube_temp': tubeTemp,
      if (motorTemp != null) 'motor_temp': motorTemp,
      if (lamTemp != null) 'lam_temp': lamTemp,
      if (motorPosition != null) 'motor_position': motorPosition,
      if (motorSpeed != null) 'motor_speed': motorSpeed,
      if (motorPower != null) 'motor_power': motorPower,
      if (motorCurrent != null) 'motor_current': motorCurrent,
      if (bandheaterPower != null) 'bandheater_power': bandheaterPower,
      if (bandheaterCurrent != null) 'bandheater_current': bandheaterCurrent,
      if (pressureSensorRaw != null) 'pressure_sensor_raw': pressureSensorRaw,
      if (waterStatus != null) 'water_status': waterStatus,
      if (weightPrediction != null) 'weight_prediction': weightPrediction,
      if (stage != null) 'stage': stage,
    });
  }

  ShotReadingsCompanion copyWith({
    Value<int>? id,
    Value<int>? shotId,
    Value<int>? timeMs,
    Value<int?>? profileMs,
    Value<double?>? pressure,
    Value<double?>? flow,
    Value<double?>? weight,
    Value<double?>? gravimetricFlow,
    Value<double?>? externalTemp1,
    Value<double?>? externalTemp2,
    Value<double?>? barUp,
    Value<double?>? barMidUp,
    Value<double?>? barMidDown,
    Value<double?>? barDown,
    Value<double?>? tubeTemp,
    Value<double?>? motorTemp,
    Value<double?>? lamTemp,
    Value<double?>? motorPosition,
    Value<double?>? motorSpeed,
    Value<double?>? motorPower,
    Value<double?>? motorCurrent,
    Value<double?>? bandheaterPower,
    Value<double?>? bandheaterCurrent,
    Value<double?>? pressureSensorRaw,
    Value<bool?>? waterStatus,
    Value<double?>? weightPrediction,
    Value<String?>? stage,
  }) {
    return ShotReadingsCompanion(
      id: id ?? this.id,
      shotId: shotId ?? this.shotId,
      timeMs: timeMs ?? this.timeMs,
      profileMs: profileMs ?? this.profileMs,
      pressure: pressure ?? this.pressure,
      flow: flow ?? this.flow,
      weight: weight ?? this.weight,
      gravimetricFlow: gravimetricFlow ?? this.gravimetricFlow,
      externalTemp1: externalTemp1 ?? this.externalTemp1,
      externalTemp2: externalTemp2 ?? this.externalTemp2,
      barUp: barUp ?? this.barUp,
      barMidUp: barMidUp ?? this.barMidUp,
      barMidDown: barMidDown ?? this.barMidDown,
      barDown: barDown ?? this.barDown,
      tubeTemp: tubeTemp ?? this.tubeTemp,
      motorTemp: motorTemp ?? this.motorTemp,
      lamTemp: lamTemp ?? this.lamTemp,
      motorPosition: motorPosition ?? this.motorPosition,
      motorSpeed: motorSpeed ?? this.motorSpeed,
      motorPower: motorPower ?? this.motorPower,
      motorCurrent: motorCurrent ?? this.motorCurrent,
      bandheaterPower: bandheaterPower ?? this.bandheaterPower,
      bandheaterCurrent: bandheaterCurrent ?? this.bandheaterCurrent,
      pressureSensorRaw: pressureSensorRaw ?? this.pressureSensorRaw,
      waterStatus: waterStatus ?? this.waterStatus,
      weightPrediction: weightPrediction ?? this.weightPrediction,
      stage: stage ?? this.stage,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (shotId.present) {
      map['shot_id'] = Variable<int>(shotId.value);
    }
    if (timeMs.present) {
      map['time_ms'] = Variable<int>(timeMs.value);
    }
    if (profileMs.present) {
      map['profile_ms'] = Variable<int>(profileMs.value);
    }
    if (pressure.present) {
      map['pressure'] = Variable<double>(pressure.value);
    }
    if (flow.present) {
      map['flow'] = Variable<double>(flow.value);
    }
    if (weight.present) {
      map['weight'] = Variable<double>(weight.value);
    }
    if (gravimetricFlow.present) {
      map['gravimetric_flow'] = Variable<double>(gravimetricFlow.value);
    }
    if (externalTemp1.present) {
      map['external_temp1'] = Variable<double>(externalTemp1.value);
    }
    if (externalTemp2.present) {
      map['external_temp2'] = Variable<double>(externalTemp2.value);
    }
    if (barUp.present) {
      map['bar_up'] = Variable<double>(barUp.value);
    }
    if (barMidUp.present) {
      map['bar_mid_up'] = Variable<double>(barMidUp.value);
    }
    if (barMidDown.present) {
      map['bar_mid_down'] = Variable<double>(barMidDown.value);
    }
    if (barDown.present) {
      map['bar_down'] = Variable<double>(barDown.value);
    }
    if (tubeTemp.present) {
      map['tube_temp'] = Variable<double>(tubeTemp.value);
    }
    if (motorTemp.present) {
      map['motor_temp'] = Variable<double>(motorTemp.value);
    }
    if (lamTemp.present) {
      map['lam_temp'] = Variable<double>(lamTemp.value);
    }
    if (motorPosition.present) {
      map['motor_position'] = Variable<double>(motorPosition.value);
    }
    if (motorSpeed.present) {
      map['motor_speed'] = Variable<double>(motorSpeed.value);
    }
    if (motorPower.present) {
      map['motor_power'] = Variable<double>(motorPower.value);
    }
    if (motorCurrent.present) {
      map['motor_current'] = Variable<double>(motorCurrent.value);
    }
    if (bandheaterPower.present) {
      map['bandheater_power'] = Variable<double>(bandheaterPower.value);
    }
    if (bandheaterCurrent.present) {
      map['bandheater_current'] = Variable<double>(bandheaterCurrent.value);
    }
    if (pressureSensorRaw.present) {
      map['pressure_sensor_raw'] = Variable<double>(pressureSensorRaw.value);
    }
    if (waterStatus.present) {
      map['water_status'] = Variable<bool>(waterStatus.value);
    }
    if (weightPrediction.present) {
      map['weight_prediction'] = Variable<double>(weightPrediction.value);
    }
    if (stage.present) {
      map['stage'] = Variable<String>(stage.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ShotReadingsCompanion(')
          ..write('id: $id, ')
          ..write('shotId: $shotId, ')
          ..write('timeMs: $timeMs, ')
          ..write('profileMs: $profileMs, ')
          ..write('pressure: $pressure, ')
          ..write('flow: $flow, ')
          ..write('weight: $weight, ')
          ..write('gravimetricFlow: $gravimetricFlow, ')
          ..write('externalTemp1: $externalTemp1, ')
          ..write('externalTemp2: $externalTemp2, ')
          ..write('barUp: $barUp, ')
          ..write('barMidUp: $barMidUp, ')
          ..write('barMidDown: $barMidDown, ')
          ..write('barDown: $barDown, ')
          ..write('tubeTemp: $tubeTemp, ')
          ..write('motorTemp: $motorTemp, ')
          ..write('lamTemp: $lamTemp, ')
          ..write('motorPosition: $motorPosition, ')
          ..write('motorSpeed: $motorSpeed, ')
          ..write('motorPower: $motorPower, ')
          ..write('motorCurrent: $motorCurrent, ')
          ..write('bandheaterPower: $bandheaterPower, ')
          ..write('bandheaterCurrent: $bandheaterCurrent, ')
          ..write('pressureSensorRaw: $pressureSensorRaw, ')
          ..write('waterStatus: $waterStatus, ')
          ..write('weightPrediction: $weightPrediction, ')
          ..write('stage: $stage')
          ..write(')'))
        .toString();
  }
}

class $StoredProfilesTable extends StoredProfiles
    with TableInfo<$StoredProfilesTable, StoredProfile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoredProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _syncIdMeta = const VerificationMeta('syncId');
  @override
  late final GeneratedColumn<String> syncId = GeneratedColumn<String>(
    'sync_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
    clientDefault: newSyncId,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    clientDefault: () => clock.now().millisecondsSinceEpoch,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<String> syncState = GeneratedColumn<String>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(SyncState.pending),
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _machineMeta = const VerificationMeta(
    'machine',
  );
  @override
  late final GeneratedColumn<String> machine = GeneratedColumn<String>(
    'machine',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('meticulous'),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _imagePathMeta = const VerificationMeta(
    'imagePath',
  );
  @override
  late final GeneratedColumn<String> imagePath = GeneratedColumn<String>(
    'image_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _customDescriptionMeta = const VerificationMeta(
    'customDescription',
  );
  @override
  late final GeneratedColumn<String> customDescription =
      GeneratedColumn<String>(
        'custom_description',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _customImagePathMeta = const VerificationMeta(
    'customImagePath',
  );
  @override
  late final GeneratedColumn<String> customImagePath = GeneratedColumn<String>(
    'custom_image_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _customImageBlobMeta = const VerificationMeta(
    'customImageBlob',
  );
  @override
  late final GeneratedColumn<String> customImageBlob = GeneratedColumn<String>(
    'custom_image_blob',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    syncId,
    updatedAt,
    deviceId,
    syncState,
    id,
    machine,
    name,
    json,
    imagePath,
    position,
    fetchedAt,
    customDescription,
    customImagePath,
    customImageBlob,
    deleted,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stored_profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredProfile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('sync_id')) {
      context.handle(
        _syncIdMeta,
        syncId.isAcceptableOrUnknown(data['sync_id']!, _syncIdMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('machine')) {
      context.handle(
        _machineMeta,
        machine.isAcceptableOrUnknown(data['machine']!, _machineMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('image_path')) {
      context.handle(
        _imagePathMeta,
        imagePath.isAcceptableOrUnknown(data['image_path']!, _imagePathMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    if (data.containsKey('custom_description')) {
      context.handle(
        _customDescriptionMeta,
        customDescription.isAcceptableOrUnknown(
          data['custom_description']!,
          _customDescriptionMeta,
        ),
      );
    }
    if (data.containsKey('custom_image_path')) {
      context.handle(
        _customImagePathMeta,
        customImagePath.isAcceptableOrUnknown(
          data['custom_image_path']!,
          _customImagePathMeta,
        ),
      );
    }
    if (data.containsKey('custom_image_blob')) {
      context.handle(
        _customImageBlobMeta,
        customImageBlob.isAcceptableOrUnknown(
          data['custom_image_blob']!,
          _customImageBlobMeta,
        ),
      );
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, machine};
  @override
  StoredProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredProfile(
      syncId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      ),
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_state'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      machine: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}machine'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      imagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_path'],
      ),
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
      customDescription: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}custom_description'],
      ),
      customImagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}custom_image_path'],
      ),
      customImageBlob: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}custom_image_blob'],
      ),
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
    );
  }

  @override
  $StoredProfilesTable createAlias(String alias) {
    return $StoredProfilesTable(attachedDatabase, alias);
  }
}

class StoredProfile extends DataClass implements Insertable<StoredProfile> {
  final String syncId;
  final int updatedAt;
  final String? deviceId;
  final String syncState;
  final String id;
  final String machine;
  final String name;
  final String json;
  final String? imagePath;
  final int position;
  final DateTime fetchedAt;
  final String? customDescription;
  final String? customImagePath;
  final String? customImageBlob;
  final bool deleted;
  const StoredProfile({
    required this.syncId,
    required this.updatedAt,
    this.deviceId,
    required this.syncState,
    required this.id,
    required this.machine,
    required this.name,
    required this.json,
    this.imagePath,
    required this.position,
    required this.fetchedAt,
    this.customDescription,
    this.customImagePath,
    this.customImageBlob,
    required this.deleted,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['sync_id'] = Variable<String>(syncId);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deviceId != null) {
      map['device_id'] = Variable<String>(deviceId);
    }
    map['sync_state'] = Variable<String>(syncState);
    map['id'] = Variable<String>(id);
    map['machine'] = Variable<String>(machine);
    map['name'] = Variable<String>(name);
    map['json'] = Variable<String>(json);
    if (!nullToAbsent || imagePath != null) {
      map['image_path'] = Variable<String>(imagePath);
    }
    map['position'] = Variable<int>(position);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    if (!nullToAbsent || customDescription != null) {
      map['custom_description'] = Variable<String>(customDescription);
    }
    if (!nullToAbsent || customImagePath != null) {
      map['custom_image_path'] = Variable<String>(customImagePath);
    }
    if (!nullToAbsent || customImageBlob != null) {
      map['custom_image_blob'] = Variable<String>(customImageBlob);
    }
    map['deleted'] = Variable<bool>(deleted);
    return map;
  }

  StoredProfilesCompanion toCompanion(bool nullToAbsent) {
    return StoredProfilesCompanion(
      syncId: Value(syncId),
      updatedAt: Value(updatedAt),
      deviceId: deviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceId),
      syncState: Value(syncState),
      id: Value(id),
      machine: Value(machine),
      name: Value(name),
      json: Value(json),
      imagePath: imagePath == null && nullToAbsent
          ? const Value.absent()
          : Value(imagePath),
      position: Value(position),
      fetchedAt: Value(fetchedAt),
      customDescription: customDescription == null && nullToAbsent
          ? const Value.absent()
          : Value(customDescription),
      customImagePath: customImagePath == null && nullToAbsent
          ? const Value.absent()
          : Value(customImagePath),
      customImageBlob: customImageBlob == null && nullToAbsent
          ? const Value.absent()
          : Value(customImageBlob),
      deleted: Value(deleted),
    );
  }

  factory StoredProfile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredProfile(
      syncId: serializer.fromJson<String>(json['syncId']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deviceId: serializer.fromJson<String?>(json['deviceId']),
      syncState: serializer.fromJson<String>(json['syncState']),
      id: serializer.fromJson<String>(json['id']),
      machine: serializer.fromJson<String>(json['machine']),
      name: serializer.fromJson<String>(json['name']),
      json: serializer.fromJson<String>(json['json']),
      imagePath: serializer.fromJson<String?>(json['imagePath']),
      position: serializer.fromJson<int>(json['position']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
      customDescription: serializer.fromJson<String?>(
        json['customDescription'],
      ),
      customImagePath: serializer.fromJson<String?>(json['customImagePath']),
      customImageBlob: serializer.fromJson<String?>(json['customImageBlob']),
      deleted: serializer.fromJson<bool>(json['deleted']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'syncId': serializer.toJson<String>(syncId),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deviceId': serializer.toJson<String?>(deviceId),
      'syncState': serializer.toJson<String>(syncState),
      'id': serializer.toJson<String>(id),
      'machine': serializer.toJson<String>(machine),
      'name': serializer.toJson<String>(name),
      'json': serializer.toJson<String>(json),
      'imagePath': serializer.toJson<String?>(imagePath),
      'position': serializer.toJson<int>(position),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
      'customDescription': serializer.toJson<String?>(customDescription),
      'customImagePath': serializer.toJson<String?>(customImagePath),
      'customImageBlob': serializer.toJson<String?>(customImageBlob),
      'deleted': serializer.toJson<bool>(deleted),
    };
  }

  StoredProfile copyWith({
    String? syncId,
    int? updatedAt,
    Value<String?> deviceId = const Value.absent(),
    String? syncState,
    String? id,
    String? machine,
    String? name,
    String? json,
    Value<String?> imagePath = const Value.absent(),
    int? position,
    DateTime? fetchedAt,
    Value<String?> customDescription = const Value.absent(),
    Value<String?> customImagePath = const Value.absent(),
    Value<String?> customImageBlob = const Value.absent(),
    bool? deleted,
  }) => StoredProfile(
    syncId: syncId ?? this.syncId,
    updatedAt: updatedAt ?? this.updatedAt,
    deviceId: deviceId.present ? deviceId.value : this.deviceId,
    syncState: syncState ?? this.syncState,
    id: id ?? this.id,
    machine: machine ?? this.machine,
    name: name ?? this.name,
    json: json ?? this.json,
    imagePath: imagePath.present ? imagePath.value : this.imagePath,
    position: position ?? this.position,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    customDescription: customDescription.present
        ? customDescription.value
        : this.customDescription,
    customImagePath: customImagePath.present
        ? customImagePath.value
        : this.customImagePath,
    customImageBlob: customImageBlob.present
        ? customImageBlob.value
        : this.customImageBlob,
    deleted: deleted ?? this.deleted,
  );
  StoredProfile copyWithCompanion(StoredProfilesCompanion data) {
    return StoredProfile(
      syncId: data.syncId.present ? data.syncId.value : this.syncId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
      id: data.id.present ? data.id.value : this.id,
      machine: data.machine.present ? data.machine.value : this.machine,
      name: data.name.present ? data.name.value : this.name,
      json: data.json.present ? data.json.value : this.json,
      imagePath: data.imagePath.present ? data.imagePath.value : this.imagePath,
      position: data.position.present ? data.position.value : this.position,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
      customDescription: data.customDescription.present
          ? data.customDescription.value
          : this.customDescription,
      customImagePath: data.customImagePath.present
          ? data.customImagePath.value
          : this.customImagePath,
      customImageBlob: data.customImageBlob.present
          ? data.customImageBlob.value
          : this.customImageBlob,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredProfile(')
          ..write('syncId: $syncId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deviceId: $deviceId, ')
          ..write('syncState: $syncState, ')
          ..write('id: $id, ')
          ..write('machine: $machine, ')
          ..write('name: $name, ')
          ..write('json: $json, ')
          ..write('imagePath: $imagePath, ')
          ..write('position: $position, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('customDescription: $customDescription, ')
          ..write('customImagePath: $customImagePath, ')
          ..write('customImageBlob: $customImageBlob, ')
          ..write('deleted: $deleted')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    syncId,
    updatedAt,
    deviceId,
    syncState,
    id,
    machine,
    name,
    json,
    imagePath,
    position,
    fetchedAt,
    customDescription,
    customImagePath,
    customImageBlob,
    deleted,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredProfile &&
          other.syncId == this.syncId &&
          other.updatedAt == this.updatedAt &&
          other.deviceId == this.deviceId &&
          other.syncState == this.syncState &&
          other.id == this.id &&
          other.machine == this.machine &&
          other.name == this.name &&
          other.json == this.json &&
          other.imagePath == this.imagePath &&
          other.position == this.position &&
          other.fetchedAt == this.fetchedAt &&
          other.customDescription == this.customDescription &&
          other.customImagePath == this.customImagePath &&
          other.customImageBlob == this.customImageBlob &&
          other.deleted == this.deleted);
}

class StoredProfilesCompanion extends UpdateCompanion<StoredProfile> {
  final Value<String> syncId;
  final Value<int> updatedAt;
  final Value<String?> deviceId;
  final Value<String> syncState;
  final Value<String> id;
  final Value<String> machine;
  final Value<String> name;
  final Value<String> json;
  final Value<String?> imagePath;
  final Value<int> position;
  final Value<DateTime> fetchedAt;
  final Value<String?> customDescription;
  final Value<String?> customImagePath;
  final Value<String?> customImageBlob;
  final Value<bool> deleted;
  final Value<int> rowid;
  const StoredProfilesCompanion({
    this.syncId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.syncState = const Value.absent(),
    this.id = const Value.absent(),
    this.machine = const Value.absent(),
    this.name = const Value.absent(),
    this.json = const Value.absent(),
    this.imagePath = const Value.absent(),
    this.position = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.customDescription = const Value.absent(),
    this.customImagePath = const Value.absent(),
    this.customImageBlob = const Value.absent(),
    this.deleted = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoredProfilesCompanion.insert({
    this.syncId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.syncState = const Value.absent(),
    required String id,
    this.machine = const Value.absent(),
    required String name,
    required String json,
    this.imagePath = const Value.absent(),
    this.position = const Value.absent(),
    required DateTime fetchedAt,
    this.customDescription = const Value.absent(),
    this.customImagePath = const Value.absent(),
    this.customImageBlob = const Value.absent(),
    this.deleted = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       json = Value(json),
       fetchedAt = Value(fetchedAt);
  static Insertable<StoredProfile> custom({
    Expression<String>? syncId,
    Expression<int>? updatedAt,
    Expression<String>? deviceId,
    Expression<String>? syncState,
    Expression<String>? id,
    Expression<String>? machine,
    Expression<String>? name,
    Expression<String>? json,
    Expression<String>? imagePath,
    Expression<int>? position,
    Expression<DateTime>? fetchedAt,
    Expression<String>? customDescription,
    Expression<String>? customImagePath,
    Expression<String>? customImageBlob,
    Expression<bool>? deleted,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (syncId != null) 'sync_id': syncId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deviceId != null) 'device_id': deviceId,
      if (syncState != null) 'sync_state': syncState,
      if (id != null) 'id': id,
      if (machine != null) 'machine': machine,
      if (name != null) 'name': name,
      if (json != null) 'json': json,
      if (imagePath != null) 'image_path': imagePath,
      if (position != null) 'position': position,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (customDescription != null) 'custom_description': customDescription,
      if (customImagePath != null) 'custom_image_path': customImagePath,
      if (customImageBlob != null) 'custom_image_blob': customImageBlob,
      if (deleted != null) 'deleted': deleted,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoredProfilesCompanion copyWith({
    Value<String>? syncId,
    Value<int>? updatedAt,
    Value<String?>? deviceId,
    Value<String>? syncState,
    Value<String>? id,
    Value<String>? machine,
    Value<String>? name,
    Value<String>? json,
    Value<String?>? imagePath,
    Value<int>? position,
    Value<DateTime>? fetchedAt,
    Value<String?>? customDescription,
    Value<String?>? customImagePath,
    Value<String?>? customImageBlob,
    Value<bool>? deleted,
    Value<int>? rowid,
  }) {
    return StoredProfilesCompanion(
      syncId: syncId ?? this.syncId,
      updatedAt: updatedAt ?? this.updatedAt,
      deviceId: deviceId ?? this.deviceId,
      syncState: syncState ?? this.syncState,
      id: id ?? this.id,
      machine: machine ?? this.machine,
      name: name ?? this.name,
      json: json ?? this.json,
      imagePath: imagePath ?? this.imagePath,
      position: position ?? this.position,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      customDescription: customDescription ?? this.customDescription,
      customImagePath: customImagePath ?? this.customImagePath,
      customImageBlob: customImageBlob ?? this.customImageBlob,
      deleted: deleted ?? this.deleted,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (syncId.present) {
      map['sync_id'] = Variable<String>(syncId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<String>(syncState.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (machine.present) {
      map['machine'] = Variable<String>(machine.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (imagePath.present) {
      map['image_path'] = Variable<String>(imagePath.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (customDescription.present) {
      map['custom_description'] = Variable<String>(customDescription.value);
    }
    if (customImagePath.present) {
      map['custom_image_path'] = Variable<String>(customImagePath.value);
    }
    if (customImageBlob.present) {
      map['custom_image_blob'] = Variable<String>(customImageBlob.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoredProfilesCompanion(')
          ..write('syncId: $syncId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deviceId: $deviceId, ')
          ..write('syncState: $syncState, ')
          ..write('id: $id, ')
          ..write('machine: $machine, ')
          ..write('name: $name, ')
          ..write('json: $json, ')
          ..write('imagePath: $imagePath, ')
          ..write('position: $position, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('customDescription: $customDescription, ')
          ..write('customImagePath: $customImagePath, ')
          ..write('customImageBlob: $customImageBlob, ')
          ..write('deleted: $deleted, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncedSettingsTable extends SyncedSettings
    with TableInfo<$SyncedSettingsTable, SyncedSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncedSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _syncIdMeta = const VerificationMeta('syncId');
  @override
  late final GeneratedColumn<String> syncId = GeneratedColumn<String>(
    'sync_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
    clientDefault: newSyncId,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    clientDefault: () => clock.now().millisecondsSinceEpoch,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<String> syncState = GeneratedColumn<String>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(SyncState.pending),
  );
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    syncId,
    updatedAt,
    deviceId,
    syncState,
    key,
    value,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'synced_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncedSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('sync_id')) {
      context.handle(
        _syncIdMeta,
        syncId.isAcceptableOrUnknown(data['sync_id']!, _syncIdMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
    }
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SyncedSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncedSetting(
      syncId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      ),
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_state'],
      )!,
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      ),
    );
  }

  @override
  $SyncedSettingsTable createAlias(String alias) {
    return $SyncedSettingsTable(attachedDatabase, alias);
  }
}

class SyncedSetting extends DataClass implements Insertable<SyncedSetting> {
  final String syncId;
  final int updatedAt;
  final String? deviceId;
  final String syncState;
  final String key;
  final String? value;
  const SyncedSetting({
    required this.syncId,
    required this.updatedAt,
    this.deviceId,
    required this.syncState,
    required this.key,
    this.value,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['sync_id'] = Variable<String>(syncId);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deviceId != null) {
      map['device_id'] = Variable<String>(deviceId);
    }
    map['sync_state'] = Variable<String>(syncState);
    map['key'] = Variable<String>(key);
    if (!nullToAbsent || value != null) {
      map['value'] = Variable<String>(value);
    }
    return map;
  }

  SyncedSettingsCompanion toCompanion(bool nullToAbsent) {
    return SyncedSettingsCompanion(
      syncId: Value(syncId),
      updatedAt: Value(updatedAt),
      deviceId: deviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceId),
      syncState: Value(syncState),
      key: Value(key),
      value: value == null && nullToAbsent
          ? const Value.absent()
          : Value(value),
    );
  }

  factory SyncedSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncedSetting(
      syncId: serializer.fromJson<String>(json['syncId']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deviceId: serializer.fromJson<String?>(json['deviceId']),
      syncState: serializer.fromJson<String>(json['syncState']),
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String?>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'syncId': serializer.toJson<String>(syncId),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deviceId': serializer.toJson<String?>(deviceId),
      'syncState': serializer.toJson<String>(syncState),
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String?>(value),
    };
  }

  SyncedSetting copyWith({
    String? syncId,
    int? updatedAt,
    Value<String?> deviceId = const Value.absent(),
    String? syncState,
    String? key,
    Value<String?> value = const Value.absent(),
  }) => SyncedSetting(
    syncId: syncId ?? this.syncId,
    updatedAt: updatedAt ?? this.updatedAt,
    deviceId: deviceId.present ? deviceId.value : this.deviceId,
    syncState: syncState ?? this.syncState,
    key: key ?? this.key,
    value: value.present ? value.value : this.value,
  );
  SyncedSetting copyWithCompanion(SyncedSettingsCompanion data) {
    return SyncedSetting(
      syncId: data.syncId.present ? data.syncId.value : this.syncId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncedSetting(')
          ..write('syncId: $syncId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deviceId: $deviceId, ')
          ..write('syncState: $syncState, ')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(syncId, updatedAt, deviceId, syncState, key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncedSetting &&
          other.syncId == this.syncId &&
          other.updatedAt == this.updatedAt &&
          other.deviceId == this.deviceId &&
          other.syncState == this.syncState &&
          other.key == this.key &&
          other.value == this.value);
}

class SyncedSettingsCompanion extends UpdateCompanion<SyncedSetting> {
  final Value<String> syncId;
  final Value<int> updatedAt;
  final Value<String?> deviceId;
  final Value<String> syncState;
  final Value<String> key;
  final Value<String?> value;
  final Value<int> rowid;
  const SyncedSettingsCompanion({
    this.syncId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.syncState = const Value.absent(),
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncedSettingsCompanion.insert({
    this.syncId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.syncState = const Value.absent(),
    required String key,
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key);
  static Insertable<SyncedSetting> custom({
    Expression<String>? syncId,
    Expression<int>? updatedAt,
    Expression<String>? deviceId,
    Expression<String>? syncState,
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (syncId != null) 'sync_id': syncId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deviceId != null) 'device_id': deviceId,
      if (syncState != null) 'sync_state': syncState,
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncedSettingsCompanion copyWith({
    Value<String>? syncId,
    Value<int>? updatedAt,
    Value<String?>? deviceId,
    Value<String>? syncState,
    Value<String>? key,
    Value<String?>? value,
    Value<int>? rowid,
  }) {
    return SyncedSettingsCompanion(
      syncId: syncId ?? this.syncId,
      updatedAt: updatedAt ?? this.updatedAt,
      deviceId: deviceId ?? this.deviceId,
      syncState: syncState ?? this.syncState,
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (syncId.present) {
      map['sync_id'] = Variable<String>(syncId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<String>(syncState.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncedSettingsCompanion(')
          ..write('syncId: $syncId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deviceId: $deviceId, ')
          ..write('syncState: $syncState, ')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $BeansTable beans = $BeansTable(this);
  late final $ShotsTable shots = $ShotsTable(this);
  late final $ShotReadingsTable shotReadings = $ShotReadingsTable(this);
  late final $StoredProfilesTable storedProfiles = $StoredProfilesTable(this);
  late final $SyncedSettingsTable syncedSettings = $SyncedSettingsTable(this);
  late final Index shotsExternalId = Index(
    'shots_external_id',
    'CREATE UNIQUE INDEX shots_external_id ON shots (external_id)',
  );
  late final Index shotReadingsShotId = Index(
    'shot_readings_shot_id',
    'CREATE INDEX shot_readings_shot_id ON shot_readings (shot_id)',
  );
  late final SyncDao syncDao = SyncDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    beans,
    shots,
    shotReadings,
    storedProfiles,
    syncedSettings,
    shotsExternalId,
    shotReadingsShotId,
  ];
}

typedef $$BeansTableCreateCompanionBuilder = BeansCompanion Function({
  Value<String> syncId,
  Value<int> updatedAt,
  Value<String?> deviceId,
  Value<String> syncState,
  Value<int> id,
  required String name,
  Value<String?> roaster,
  Value<DateTime?> roastDate,
  Value<bool?> isBlend,
  Value<String?> roastedFor,
  Value<String?> roastLevel,
  Value<String?> country,
  Value<String?> processing,
  Value<String?> variety,
  Value<String?> producer,
  Value<double?> weightGrams,
  Value<String?> taste,
  Value<double?> cost,
  Value<String?> photoPath,
  Value<String?> photoBlob,
  Value<bool> isFrozen,
  Value<DateTime?> thawedDate,
  Value<DateTime?> emptiedAt,
  Value<DateTime> createdAt,
  Value<bool> deleted,
});
typedef $$BeansTableUpdateCompanionBuilder = BeansCompanion Function({
  Value<String> syncId,
  Value<int> updatedAt,
  Value<String?> deviceId,
  Value<String> syncState,
  Value<int> id,
  Value<String> name,
  Value<String?> roaster,
  Value<DateTime?> roastDate,
  Value<bool?> isBlend,
  Value<String?> roastedFor,
  Value<String?> roastLevel,
  Value<String?> country,
  Value<String?> processing,
  Value<String?> variety,
  Value<String?> producer,
  Value<double?> weightGrams,
  Value<String?> taste,
  Value<double?> cost,
  Value<String?> photoPath,
  Value<String?> photoBlob,
  Value<bool> isFrozen,
  Value<DateTime?> thawedDate,
  Value<DateTime?> emptiedAt,
  Value<DateTime> createdAt,
  Value<bool> deleted,
});

final class $$BeansTableReferences
    extends BaseReferences<_$AppDatabase, $BeansTable, Bean> {
  $$BeansTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ShotsTable, List<Shot>> _shotsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.shots,
    aliasName: 'beans__id__shots__bean_id',
  );

  $$ShotsTableProcessedTableManager get shotsRefs {
    final manager = $$ShotsTableTableManager(
      $_db,
      $_db.shots,
    ).filter((f) => f.beanId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_shotsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$BeansTableFilterComposer extends Composer<_$AppDatabase, $BeansTable> {
  $$BeansTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get syncId => $composableBuilder(
    column: $table.syncId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get roaster => $composableBuilder(
    column: $table.roaster,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get roastDate => $composableBuilder(
    column: $table.roastDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isBlend => $composableBuilder(
    column: $table.isBlend,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get roastedFor => $composableBuilder(
    column: $table.roastedFor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get roastLevel => $composableBuilder(
    column: $table.roastLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get country => $composableBuilder(
    column: $table.country,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get processing => $composableBuilder(
    column: $table.processing,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get variety => $composableBuilder(
    column: $table.variety,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get producer => $composableBuilder(
    column: $table.producer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get weightGrams => $composableBuilder(
    column: $table.weightGrams,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get taste => $composableBuilder(
    column: $table.taste,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get cost => $composableBuilder(
    column: $table.cost,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get photoPath => $composableBuilder(
    column: $table.photoPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get photoBlob => $composableBuilder(
    column: $table.photoBlob,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFrozen => $composableBuilder(
    column: $table.isFrozen,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get thawedDate => $composableBuilder(
    column: $table.thawedDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get emptiedAt => $composableBuilder(
    column: $table.emptiedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> shotsRefs(
    Expression<bool> Function($$ShotsTableFilterComposer f) f,
  ) {
    final $$ShotsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.shots,
      getReferencedColumn: (t) => t.beanId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShotsTableFilterComposer(
            $db: $db,
            $table: $db.shots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BeansTableOrderingComposer
    extends Composer<_$AppDatabase, $BeansTable> {
  $$BeansTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get syncId => $composableBuilder(
    column: $table.syncId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get roaster => $composableBuilder(
    column: $table.roaster,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get roastDate => $composableBuilder(
    column: $table.roastDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isBlend => $composableBuilder(
    column: $table.isBlend,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get roastedFor => $composableBuilder(
    column: $table.roastedFor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get roastLevel => $composableBuilder(
    column: $table.roastLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get country => $composableBuilder(
    column: $table.country,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get processing => $composableBuilder(
    column: $table.processing,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get variety => $composableBuilder(
    column: $table.variety,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get producer => $composableBuilder(
    column: $table.producer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get weightGrams => $composableBuilder(
    column: $table.weightGrams,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get taste => $composableBuilder(
    column: $table.taste,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get cost => $composableBuilder(
    column: $table.cost,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get photoPath => $composableBuilder(
    column: $table.photoPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get photoBlob => $composableBuilder(
    column: $table.photoBlob,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFrozen => $composableBuilder(
    column: $table.isFrozen,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get thawedDate => $composableBuilder(
    column: $table.thawedDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get emptiedAt => $composableBuilder(
    column: $table.emptiedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BeansTableAnnotationComposer
    extends Composer<_$AppDatabase, $BeansTable> {
  $$BeansTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get syncId =>
      $composableBuilder(column: $table.syncId, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);

  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get roaster =>
      $composableBuilder(column: $table.roaster, builder: (column) => column);

  GeneratedColumn<DateTime> get roastDate =>
      $composableBuilder(column: $table.roastDate, builder: (column) => column);

  GeneratedColumn<bool> get isBlend =>
      $composableBuilder(column: $table.isBlend, builder: (column) => column);

  GeneratedColumn<String> get roastedFor => $composableBuilder(
    column: $table.roastedFor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get roastLevel => $composableBuilder(
    column: $table.roastLevel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get country =>
      $composableBuilder(column: $table.country, builder: (column) => column);

  GeneratedColumn<String> get processing => $composableBuilder(
    column: $table.processing,
    builder: (column) => column,
  );

  GeneratedColumn<String> get variety =>
      $composableBuilder(column: $table.variety, builder: (column) => column);

  GeneratedColumn<String> get producer =>
      $composableBuilder(column: $table.producer, builder: (column) => column);

  GeneratedColumn<double> get weightGrams => $composableBuilder(
    column: $table.weightGrams,
    builder: (column) => column,
  );

  GeneratedColumn<String> get taste =>
      $composableBuilder(column: $table.taste, builder: (column) => column);

  GeneratedColumn<double> get cost =>
      $composableBuilder(column: $table.cost, builder: (column) => column);

  GeneratedColumn<String> get photoPath =>
      $composableBuilder(column: $table.photoPath, builder: (column) => column);

  GeneratedColumn<String> get photoBlob =>
      $composableBuilder(column: $table.photoBlob, builder: (column) => column);

  GeneratedColumn<bool> get isFrozen =>
      $composableBuilder(column: $table.isFrozen, builder: (column) => column);

  GeneratedColumn<DateTime> get thawedDate => $composableBuilder(
    column: $table.thawedDate,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get emptiedAt =>
      $composableBuilder(column: $table.emptiedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  Expression<T> shotsRefs<T extends Object>(
    Expression<T> Function($$ShotsTableAnnotationComposer a) f,
  ) {
    final $$ShotsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.shots,
      getReferencedColumn: (t) => t.beanId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShotsTableAnnotationComposer(
            $db: $db,
            $table: $db.shots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BeansTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BeansTable,
          Bean,
          $$BeansTableFilterComposer,
          $$BeansTableOrderingComposer,
          $$BeansTableAnnotationComposer,
          $$BeansTableCreateCompanionBuilder,
          $$BeansTableUpdateCompanionBuilder,
          (Bean, $$BeansTableReferences),
          Bean,
          PrefetchHooks Function({bool shotsRefs})
        > {
  $$BeansTableTableManager(_$AppDatabase db, $BeansTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BeansTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BeansTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BeansTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> syncId = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String?> deviceId = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> roaster = const Value.absent(),
                Value<DateTime?> roastDate = const Value.absent(),
                Value<bool?> isBlend = const Value.absent(),
                Value<String?> roastedFor = const Value.absent(),
                Value<String?> roastLevel = const Value.absent(),
                Value<String?> country = const Value.absent(),
                Value<String?> processing = const Value.absent(),
                Value<String?> variety = const Value.absent(),
                Value<String?> producer = const Value.absent(),
                Value<double?> weightGrams = const Value.absent(),
                Value<String?> taste = const Value.absent(),
                Value<double?> cost = const Value.absent(),
                Value<String?> photoPath = const Value.absent(),
                Value<String?> photoBlob = const Value.absent(),
                Value<bool> isFrozen = const Value.absent(),
                Value<DateTime?> thawedDate = const Value.absent(),
                Value<DateTime?> emptiedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
              }) => BeansCompanion(
                syncId: syncId,
                updatedAt: updatedAt,
                deviceId: deviceId,
                syncState: syncState,
                id: id,
                name: name,
                roaster: roaster,
                roastDate: roastDate,
                isBlend: isBlend,
                roastedFor: roastedFor,
                roastLevel: roastLevel,
                country: country,
                processing: processing,
                variety: variety,
                producer: producer,
                weightGrams: weightGrams,
                taste: taste,
                cost: cost,
                photoPath: photoPath,
                photoBlob: photoBlob,
                isFrozen: isFrozen,
                thawedDate: thawedDate,
                emptiedAt: emptiedAt,
                createdAt: createdAt,
                deleted: deleted,
              ),
          createCompanionCallback:
              ({
                Value<String> syncId = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String?> deviceId = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<int> id = const Value.absent(),
                required String name,
                Value<String?> roaster = const Value.absent(),
                Value<DateTime?> roastDate = const Value.absent(),
                Value<bool?> isBlend = const Value.absent(),
                Value<String?> roastedFor = const Value.absent(),
                Value<String?> roastLevel = const Value.absent(),
                Value<String?> country = const Value.absent(),
                Value<String?> processing = const Value.absent(),
                Value<String?> variety = const Value.absent(),
                Value<String?> producer = const Value.absent(),
                Value<double?> weightGrams = const Value.absent(),
                Value<String?> taste = const Value.absent(),
                Value<double?> cost = const Value.absent(),
                Value<String?> photoPath = const Value.absent(),
                Value<String?> photoBlob = const Value.absent(),
                Value<bool> isFrozen = const Value.absent(),
                Value<DateTime?> thawedDate = const Value.absent(),
                Value<DateTime?> emptiedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
              }) => BeansCompanion.insert(
                syncId: syncId,
                updatedAt: updatedAt,
                deviceId: deviceId,
                syncState: syncState,
                id: id,
                name: name,
                roaster: roaster,
                roastDate: roastDate,
                isBlend: isBlend,
                roastedFor: roastedFor,
                roastLevel: roastLevel,
                country: country,
                processing: processing,
                variety: variety,
                producer: producer,
                weightGrams: weightGrams,
                taste: taste,
                cost: cost,
                photoPath: photoPath,
                photoBlob: photoBlob,
                isFrozen: isFrozen,
                thawedDate: thawedDate,
                emptiedAt: emptiedAt,
                createdAt: createdAt,
                deleted: deleted,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BeansTable, Bean>(table),
                  $$BeansTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({shotsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (shotsRefs) db.shots],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (shotsRefs)
                    await $_getPrefetchedData<Bean, $BeansTable, Shot>(
                      currentTable: table,
                      referencedTable: $$BeansTableReferences._shotsRefsTable(
                        db,
                      ),
                      managerFromTypedResult: (p0) =>
                          $$BeansTableReferences(db, table, p0).shotsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.beanId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$BeansTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BeansTable,
      Bean,
      $$BeansTableFilterComposer,
      $$BeansTableOrderingComposer,
      $$BeansTableAnnotationComposer,
      $$BeansTableCreateCompanionBuilder,
      $$BeansTableUpdateCompanionBuilder,
      (Bean, $$BeansTableReferences),
      Bean,
      PrefetchHooks Function({bool shotsRefs})
    >;
typedef $$ShotsTableCreateCompanionBuilder = ShotsCompanion Function({
  Value<String> syncId,
  Value<int> updatedAt,
  Value<String?> deviceId,
  Value<String> syncState,
  Value<int> id,
  required DateTime timestamp,
  Value<int?> beanId,
  Value<String?> profileName,
  Value<double?> doseGrams,
  Value<double?> finalWeight,
  Value<int?> durationMs,
  Value<String?> grindSize,
  Value<String?> grinder,
  Value<String?> burrs,
  Value<String?> brewedWith,
  Value<String?> brewChainId,
  Value<double?> grindZero,
  Value<String?> grindMarker,
  Value<int?> rating,
  Value<int?> tasteFinish,
  Value<int?> tasteBody,
  Value<int?> tasteAcidity,
  Value<int?> tasteSweetness,
  Value<int?> tasteHollow,
  Value<int?> tasteSalty,
  Value<int?> tasteAstringent,
  Value<int?> tasteBitter,
  Value<String?> tasteExtras,
  Value<String?> notes,
  Value<String?> shotPhotoPath,
  Value<String?> rawDebugJson,
  Value<DateTime> createdAt,
  Value<String?> externalId,
  Value<String> machine,
  Value<String?> profileColor,
  Value<String?> profileImagePath,
  Value<double?> brewTemp,
  Value<double?> profileTemp,
  Value<DateTime?> deletedAt,
  Value<String?> aiAnalysis,
  Value<String?> profileJson,
  Value<String?> stageExits,
  Value<String?> aiAnalysisModel,
  Value<DateTime?> aiAnalysedAt,
});
typedef $$ShotsTableUpdateCompanionBuilder = ShotsCompanion Function({
  Value<String> syncId,
  Value<int> updatedAt,
  Value<String?> deviceId,
  Value<String> syncState,
  Value<int> id,
  Value<DateTime> timestamp,
  Value<int?> beanId,
  Value<String?> profileName,
  Value<double?> doseGrams,
  Value<double?> finalWeight,
  Value<int?> durationMs,
  Value<String?> grindSize,
  Value<String?> grinder,
  Value<String?> burrs,
  Value<String?> brewedWith,
  Value<String?> brewChainId,
  Value<double?> grindZero,
  Value<String?> grindMarker,
  Value<int?> rating,
  Value<int?> tasteFinish,
  Value<int?> tasteBody,
  Value<int?> tasteAcidity,
  Value<int?> tasteSweetness,
  Value<int?> tasteHollow,
  Value<int?> tasteSalty,
  Value<int?> tasteAstringent,
  Value<int?> tasteBitter,
  Value<String?> tasteExtras,
  Value<String?> notes,
  Value<String?> shotPhotoPath,
  Value<String?> rawDebugJson,
  Value<DateTime> createdAt,
  Value<String?> externalId,
  Value<String> machine,
  Value<String?> profileColor,
  Value<String?> profileImagePath,
  Value<double?> brewTemp,
  Value<double?> profileTemp,
  Value<DateTime?> deletedAt,
  Value<String?> aiAnalysis,
  Value<String?> profileJson,
  Value<String?> stageExits,
  Value<String?> aiAnalysisModel,
  Value<DateTime?> aiAnalysedAt,
});

final class $$ShotsTableReferences
    extends BaseReferences<_$AppDatabase, $ShotsTable, Shot> {
  $$ShotsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BeansTable _beanIdTable(_$AppDatabase db) =>
      db.beans.createAlias('shots__bean_id__beans__id');

  $$BeansTableProcessedTableManager? get beanId {
    final $_column = $_itemColumn<int>('bean_id');
    if ($_column == null) return null;
    final manager = $$BeansTableTableManager(
      $_db,
      $_db.beans,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_beanIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ShotReadingsTable, List<ShotReading>>
  _shotReadingsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.shotReadings,
    aliasName: 'shots__id__shot_readings__shot_id',
  );

  $$ShotReadingsTableProcessedTableManager get shotReadingsRefs {
    final manager = $$ShotReadingsTableTableManager(
      $_db,
      $_db.shotReadings,
    ).filter((f) => f.shotId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_shotReadingsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ShotsTableFilterComposer extends Composer<_$AppDatabase, $ShotsTable> {
  $$ShotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get syncId => $composableBuilder(
    column: $table.syncId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get profileName => $composableBuilder(
    column: $table.profileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get doseGrams => $composableBuilder(
    column: $table.doseGrams,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get finalWeight => $composableBuilder(
    column: $table.finalWeight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get grindSize => $composableBuilder(
    column: $table.grindSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get grinder => $composableBuilder(
    column: $table.grinder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get burrs => $composableBuilder(
    column: $table.burrs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get brewedWith => $composableBuilder(
    column: $table.brewedWith,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get brewChainId => $composableBuilder(
    column: $table.brewChainId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get grindZero => $composableBuilder(
    column: $table.grindZero,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get grindMarker => $composableBuilder(
    column: $table.grindMarker,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tasteFinish => $composableBuilder(
    column: $table.tasteFinish,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tasteBody => $composableBuilder(
    column: $table.tasteBody,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tasteAcidity => $composableBuilder(
    column: $table.tasteAcidity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tasteSweetness => $composableBuilder(
    column: $table.tasteSweetness,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tasteHollow => $composableBuilder(
    column: $table.tasteHollow,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tasteSalty => $composableBuilder(
    column: $table.tasteSalty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tasteAstringent => $composableBuilder(
    column: $table.tasteAstringent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tasteBitter => $composableBuilder(
    column: $table.tasteBitter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tasteExtras => $composableBuilder(
    column: $table.tasteExtras,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get shotPhotoPath => $composableBuilder(
    column: $table.shotPhotoPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawDebugJson => $composableBuilder(
    column: $table.rawDebugJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get externalId => $composableBuilder(
    column: $table.externalId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get machine => $composableBuilder(
    column: $table.machine,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get profileColor => $composableBuilder(
    column: $table.profileColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get profileImagePath => $composableBuilder(
    column: $table.profileImagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get brewTemp => $composableBuilder(
    column: $table.brewTemp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get profileTemp => $composableBuilder(
    column: $table.profileTemp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aiAnalysis => $composableBuilder(
    column: $table.aiAnalysis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get profileJson => $composableBuilder(
    column: $table.profileJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stageExits => $composableBuilder(
    column: $table.stageExits,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aiAnalysisModel => $composableBuilder(
    column: $table.aiAnalysisModel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get aiAnalysedAt => $composableBuilder(
    column: $table.aiAnalysedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BeansTableFilterComposer get beanId {
    final $$BeansTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.beanId,
      referencedTable: $db.beans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BeansTableFilterComposer(
            $db: $db,
            $table: $db.beans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> shotReadingsRefs(
    Expression<bool> Function($$ShotReadingsTableFilterComposer f) f,
  ) {
    final $$ShotReadingsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.shotReadings,
      getReferencedColumn: (t) => t.shotId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShotReadingsTableFilterComposer(
            $db: $db,
            $table: $db.shotReadings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ShotsTableOrderingComposer
    extends Composer<_$AppDatabase, $ShotsTable> {
  $$ShotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get syncId => $composableBuilder(
    column: $table.syncId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get profileName => $composableBuilder(
    column: $table.profileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get doseGrams => $composableBuilder(
    column: $table.doseGrams,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get finalWeight => $composableBuilder(
    column: $table.finalWeight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get grindSize => $composableBuilder(
    column: $table.grindSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get grinder => $composableBuilder(
    column: $table.grinder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get burrs => $composableBuilder(
    column: $table.burrs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get brewedWith => $composableBuilder(
    column: $table.brewedWith,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get brewChainId => $composableBuilder(
    column: $table.brewChainId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get grindZero => $composableBuilder(
    column: $table.grindZero,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get grindMarker => $composableBuilder(
    column: $table.grindMarker,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tasteFinish => $composableBuilder(
    column: $table.tasteFinish,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tasteBody => $composableBuilder(
    column: $table.tasteBody,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tasteAcidity => $composableBuilder(
    column: $table.tasteAcidity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tasteSweetness => $composableBuilder(
    column: $table.tasteSweetness,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tasteHollow => $composableBuilder(
    column: $table.tasteHollow,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tasteSalty => $composableBuilder(
    column: $table.tasteSalty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tasteAstringent => $composableBuilder(
    column: $table.tasteAstringent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tasteBitter => $composableBuilder(
    column: $table.tasteBitter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tasteExtras => $composableBuilder(
    column: $table.tasteExtras,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get shotPhotoPath => $composableBuilder(
    column: $table.shotPhotoPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawDebugJson => $composableBuilder(
    column: $table.rawDebugJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get externalId => $composableBuilder(
    column: $table.externalId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get machine => $composableBuilder(
    column: $table.machine,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get profileColor => $composableBuilder(
    column: $table.profileColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get profileImagePath => $composableBuilder(
    column: $table.profileImagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get brewTemp => $composableBuilder(
    column: $table.brewTemp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get profileTemp => $composableBuilder(
    column: $table.profileTemp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aiAnalysis => $composableBuilder(
    column: $table.aiAnalysis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get profileJson => $composableBuilder(
    column: $table.profileJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stageExits => $composableBuilder(
    column: $table.stageExits,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aiAnalysisModel => $composableBuilder(
    column: $table.aiAnalysisModel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get aiAnalysedAt => $composableBuilder(
    column: $table.aiAnalysedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BeansTableOrderingComposer get beanId {
    final $$BeansTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.beanId,
      referencedTable: $db.beans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BeansTableOrderingComposer(
            $db: $db,
            $table: $db.beans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ShotsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ShotsTable> {
  $$ShotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get syncId =>
      $composableBuilder(column: $table.syncId, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);

  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<String> get profileName => $composableBuilder(
    column: $table.profileName,
    builder: (column) => column,
  );

  GeneratedColumn<double> get doseGrams =>
      $composableBuilder(column: $table.doseGrams, builder: (column) => column);

  GeneratedColumn<double> get finalWeight => $composableBuilder(
    column: $table.finalWeight,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get grindSize =>
      $composableBuilder(column: $table.grindSize, builder: (column) => column);

  GeneratedColumn<String> get grinder =>
      $composableBuilder(column: $table.grinder, builder: (column) => column);

  GeneratedColumn<String> get burrs =>
      $composableBuilder(column: $table.burrs, builder: (column) => column);

  GeneratedColumn<String> get brewedWith => $composableBuilder(
    column: $table.brewedWith,
    builder: (column) => column,
  );

  GeneratedColumn<String> get brewChainId => $composableBuilder(
    column: $table.brewChainId,
    builder: (column) => column,
  );

  GeneratedColumn<double> get grindZero =>
      $composableBuilder(column: $table.grindZero, builder: (column) => column);

  GeneratedColumn<String> get grindMarker => $composableBuilder(
    column: $table.grindMarker,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);

  GeneratedColumn<int> get tasteFinish => $composableBuilder(
    column: $table.tasteFinish,
    builder: (column) => column,
  );

  GeneratedColumn<int> get tasteBody =>
      $composableBuilder(column: $table.tasteBody, builder: (column) => column);

  GeneratedColumn<int> get tasteAcidity => $composableBuilder(
    column: $table.tasteAcidity,
    builder: (column) => column,
  );

  GeneratedColumn<int> get tasteSweetness => $composableBuilder(
    column: $table.tasteSweetness,
    builder: (column) => column,
  );

  GeneratedColumn<int> get tasteHollow => $composableBuilder(
    column: $table.tasteHollow,
    builder: (column) => column,
  );

  GeneratedColumn<int> get tasteSalty => $composableBuilder(
    column: $table.tasteSalty,
    builder: (column) => column,
  );

  GeneratedColumn<int> get tasteAstringent => $composableBuilder(
    column: $table.tasteAstringent,
    builder: (column) => column,
  );

  GeneratedColumn<int> get tasteBitter => $composableBuilder(
    column: $table.tasteBitter,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tasteExtras => $composableBuilder(
    column: $table.tasteExtras,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get shotPhotoPath => $composableBuilder(
    column: $table.shotPhotoPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rawDebugJson => $composableBuilder(
    column: $table.rawDebugJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get externalId => $composableBuilder(
    column: $table.externalId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get machine =>
      $composableBuilder(column: $table.machine, builder: (column) => column);

  GeneratedColumn<String> get profileColor => $composableBuilder(
    column: $table.profileColor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get profileImagePath => $composableBuilder(
    column: $table.profileImagePath,
    builder: (column) => column,
  );

  GeneratedColumn<double> get brewTemp =>
      $composableBuilder(column: $table.brewTemp, builder: (column) => column);

  GeneratedColumn<double> get profileTemp => $composableBuilder(
    column: $table.profileTemp,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get aiAnalysis => $composableBuilder(
    column: $table.aiAnalysis,
    builder: (column) => column,
  );

  GeneratedColumn<String> get profileJson => $composableBuilder(
    column: $table.profileJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get stageExits => $composableBuilder(
    column: $table.stageExits,
    builder: (column) => column,
  );

  GeneratedColumn<String> get aiAnalysisModel => $composableBuilder(
    column: $table.aiAnalysisModel,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get aiAnalysedAt => $composableBuilder(
    column: $table.aiAnalysedAt,
    builder: (column) => column,
  );

  $$BeansTableAnnotationComposer get beanId {
    final $$BeansTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.beanId,
      referencedTable: $db.beans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BeansTableAnnotationComposer(
            $db: $db,
            $table: $db.beans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> shotReadingsRefs<T extends Object>(
    Expression<T> Function($$ShotReadingsTableAnnotationComposer a) f,
  ) {
    final $$ShotReadingsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.shotReadings,
      getReferencedColumn: (t) => t.shotId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShotReadingsTableAnnotationComposer(
            $db: $db,
            $table: $db.shotReadings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ShotsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ShotsTable,
          Shot,
          $$ShotsTableFilterComposer,
          $$ShotsTableOrderingComposer,
          $$ShotsTableAnnotationComposer,
          $$ShotsTableCreateCompanionBuilder,
          $$ShotsTableUpdateCompanionBuilder,
          (Shot, $$ShotsTableReferences),
          Shot,
          PrefetchHooks Function({bool beanId, bool shotReadingsRefs})
        > {
  $$ShotsTableTableManager(_$AppDatabase db, $ShotsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ShotsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ShotsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ShotsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> syncId = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String?> deviceId = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<int> id = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<int?> beanId = const Value.absent(),
                Value<String?> profileName = const Value.absent(),
                Value<double?> doseGrams = const Value.absent(),
                Value<double?> finalWeight = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String?> grindSize = const Value.absent(),
                Value<String?> grinder = const Value.absent(),
                Value<String?> burrs = const Value.absent(),
                Value<String?> brewedWith = const Value.absent(),
                Value<String?> brewChainId = const Value.absent(),
                Value<double?> grindZero = const Value.absent(),
                Value<String?> grindMarker = const Value.absent(),
                Value<int?> rating = const Value.absent(),
                Value<int?> tasteFinish = const Value.absent(),
                Value<int?> tasteBody = const Value.absent(),
                Value<int?> tasteAcidity = const Value.absent(),
                Value<int?> tasteSweetness = const Value.absent(),
                Value<int?> tasteHollow = const Value.absent(),
                Value<int?> tasteSalty = const Value.absent(),
                Value<int?> tasteAstringent = const Value.absent(),
                Value<int?> tasteBitter = const Value.absent(),
                Value<String?> tasteExtras = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> shotPhotoPath = const Value.absent(),
                Value<String?> rawDebugJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String?> externalId = const Value.absent(),
                Value<String> machine = const Value.absent(),
                Value<String?> profileColor = const Value.absent(),
                Value<String?> profileImagePath = const Value.absent(),
                Value<double?> brewTemp = const Value.absent(),
                Value<double?> profileTemp = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String?> aiAnalysis = const Value.absent(),
                Value<String?> profileJson = const Value.absent(),
                Value<String?> stageExits = const Value.absent(),
                Value<String?> aiAnalysisModel = const Value.absent(),
                Value<DateTime?> aiAnalysedAt = const Value.absent(),
              }) => ShotsCompanion(
                syncId: syncId,
                updatedAt: updatedAt,
                deviceId: deviceId,
                syncState: syncState,
                id: id,
                timestamp: timestamp,
                beanId: beanId,
                profileName: profileName,
                doseGrams: doseGrams,
                finalWeight: finalWeight,
                durationMs: durationMs,
                grindSize: grindSize,
                grinder: grinder,
                burrs: burrs,
                brewedWith: brewedWith,
                brewChainId: brewChainId,
                grindZero: grindZero,
                grindMarker: grindMarker,
                rating: rating,
                tasteFinish: tasteFinish,
                tasteBody: tasteBody,
                tasteAcidity: tasteAcidity,
                tasteSweetness: tasteSweetness,
                tasteHollow: tasteHollow,
                tasteSalty: tasteSalty,
                tasteAstringent: tasteAstringent,
                tasteBitter: tasteBitter,
                tasteExtras: tasteExtras,
                notes: notes,
                shotPhotoPath: shotPhotoPath,
                rawDebugJson: rawDebugJson,
                createdAt: createdAt,
                externalId: externalId,
                machine: machine,
                profileColor: profileColor,
                profileImagePath: profileImagePath,
                brewTemp: brewTemp,
                profileTemp: profileTemp,
                deletedAt: deletedAt,
                aiAnalysis: aiAnalysis,
                profileJson: profileJson,
                stageExits: stageExits,
                aiAnalysisModel: aiAnalysisModel,
                aiAnalysedAt: aiAnalysedAt,
              ),
          createCompanionCallback:
              ({
                Value<String> syncId = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String?> deviceId = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<int> id = const Value.absent(),
                required DateTime timestamp,
                Value<int?> beanId = const Value.absent(),
                Value<String?> profileName = const Value.absent(),
                Value<double?> doseGrams = const Value.absent(),
                Value<double?> finalWeight = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String?> grindSize = const Value.absent(),
                Value<String?> grinder = const Value.absent(),
                Value<String?> burrs = const Value.absent(),
                Value<String?> brewedWith = const Value.absent(),
                Value<String?> brewChainId = const Value.absent(),
                Value<double?> grindZero = const Value.absent(),
                Value<String?> grindMarker = const Value.absent(),
                Value<int?> rating = const Value.absent(),
                Value<int?> tasteFinish = const Value.absent(),
                Value<int?> tasteBody = const Value.absent(),
                Value<int?> tasteAcidity = const Value.absent(),
                Value<int?> tasteSweetness = const Value.absent(),
                Value<int?> tasteHollow = const Value.absent(),
                Value<int?> tasteSalty = const Value.absent(),
                Value<int?> tasteAstringent = const Value.absent(),
                Value<int?> tasteBitter = const Value.absent(),
                Value<String?> tasteExtras = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> shotPhotoPath = const Value.absent(),
                Value<String?> rawDebugJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String?> externalId = const Value.absent(),
                Value<String> machine = const Value.absent(),
                Value<String?> profileColor = const Value.absent(),
                Value<String?> profileImagePath = const Value.absent(),
                Value<double?> brewTemp = const Value.absent(),
                Value<double?> profileTemp = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String?> aiAnalysis = const Value.absent(),
                Value<String?> profileJson = const Value.absent(),
                Value<String?> stageExits = const Value.absent(),
                Value<String?> aiAnalysisModel = const Value.absent(),
                Value<DateTime?> aiAnalysedAt = const Value.absent(),
              }) => ShotsCompanion.insert(
                syncId: syncId,
                updatedAt: updatedAt,
                deviceId: deviceId,
                syncState: syncState,
                id: id,
                timestamp: timestamp,
                beanId: beanId,
                profileName: profileName,
                doseGrams: doseGrams,
                finalWeight: finalWeight,
                durationMs: durationMs,
                grindSize: grindSize,
                grinder: grinder,
                burrs: burrs,
                brewedWith: brewedWith,
                brewChainId: brewChainId,
                grindZero: grindZero,
                grindMarker: grindMarker,
                rating: rating,
                tasteFinish: tasteFinish,
                tasteBody: tasteBody,
                tasteAcidity: tasteAcidity,
                tasteSweetness: tasteSweetness,
                tasteHollow: tasteHollow,
                tasteSalty: tasteSalty,
                tasteAstringent: tasteAstringent,
                tasteBitter: tasteBitter,
                tasteExtras: tasteExtras,
                notes: notes,
                shotPhotoPath: shotPhotoPath,
                rawDebugJson: rawDebugJson,
                createdAt: createdAt,
                externalId: externalId,
                machine: machine,
                profileColor: profileColor,
                profileImagePath: profileImagePath,
                brewTemp: brewTemp,
                profileTemp: profileTemp,
                deletedAt: deletedAt,
                aiAnalysis: aiAnalysis,
                profileJson: profileJson,
                stageExits: stageExits,
                aiAnalysisModel: aiAnalysisModel,
                aiAnalysedAt: aiAnalysedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ShotsTable, Shot>(table),
                  $$ShotsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({beanId = false, shotReadingsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (shotReadingsRefs) db.shotReadings],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (beanId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.beanId,
                        referencedTable: $$ShotsTableReferences._beanIdTable(
                          db,
                        ),
                        referencedColumn: $$ShotsTableReferences
                            ._beanIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (shotReadingsRefs)
                    await $_getPrefetchedData<Shot, $ShotsTable, ShotReading>(
                      currentTable: table,
                      referencedTable: $$ShotsTableReferences
                          ._shotReadingsRefsTable(db),
                      managerFromTypedResult: (p0) => $$ShotsTableReferences(
                        db,
                        table,
                        p0,
                      ).shotReadingsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.shotId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ShotsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ShotsTable,
      Shot,
      $$ShotsTableFilterComposer,
      $$ShotsTableOrderingComposer,
      $$ShotsTableAnnotationComposer,
      $$ShotsTableCreateCompanionBuilder,
      $$ShotsTableUpdateCompanionBuilder,
      (Shot, $$ShotsTableReferences),
      Shot,
      PrefetchHooks Function({bool beanId, bool shotReadingsRefs})
    >;
typedef $$ShotReadingsTableCreateCompanionBuilder =
    ShotReadingsCompanion Function({
      Value<int> id,
      required int shotId,
      required int timeMs,
      Value<int?> profileMs,
      Value<double?> pressure,
      Value<double?> flow,
      Value<double?> weight,
      Value<double?> gravimetricFlow,
      Value<double?> externalTemp1,
      Value<double?> externalTemp2,
      Value<double?> barUp,
      Value<double?> barMidUp,
      Value<double?> barMidDown,
      Value<double?> barDown,
      Value<double?> tubeTemp,
      Value<double?> motorTemp,
      Value<double?> lamTemp,
      Value<double?> motorPosition,
      Value<double?> motorSpeed,
      Value<double?> motorPower,
      Value<double?> motorCurrent,
      Value<double?> bandheaterPower,
      Value<double?> bandheaterCurrent,
      Value<double?> pressureSensorRaw,
      Value<bool?> waterStatus,
      Value<double?> weightPrediction,
      Value<String?> stage,
    });
typedef $$ShotReadingsTableUpdateCompanionBuilder =
    ShotReadingsCompanion Function({
      Value<int> id,
      Value<int> shotId,
      Value<int> timeMs,
      Value<int?> profileMs,
      Value<double?> pressure,
      Value<double?> flow,
      Value<double?> weight,
      Value<double?> gravimetricFlow,
      Value<double?> externalTemp1,
      Value<double?> externalTemp2,
      Value<double?> barUp,
      Value<double?> barMidUp,
      Value<double?> barMidDown,
      Value<double?> barDown,
      Value<double?> tubeTemp,
      Value<double?> motorTemp,
      Value<double?> lamTemp,
      Value<double?> motorPosition,
      Value<double?> motorSpeed,
      Value<double?> motorPower,
      Value<double?> motorCurrent,
      Value<double?> bandheaterPower,
      Value<double?> bandheaterCurrent,
      Value<double?> pressureSensorRaw,
      Value<bool?> waterStatus,
      Value<double?> weightPrediction,
      Value<String?> stage,
    });

final class $$ShotReadingsTableReferences
    extends BaseReferences<_$AppDatabase, $ShotReadingsTable, ShotReading> {
  $$ShotReadingsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ShotsTable _shotIdTable(_$AppDatabase db) =>
      db.shots.createAlias('shot_readings__shot_id__shots__id');

  $$ShotsTableProcessedTableManager get shotId {
    final $_column = $_itemColumn<int>('shot_id')!;

    final manager = $$ShotsTableTableManager(
      $_db,
      $_db.shots,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_shotIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ShotReadingsTableFilterComposer
    extends Composer<_$AppDatabase, $ShotReadingsTable> {
  $$ShotReadingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timeMs => $composableBuilder(
    column: $table.timeMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get profileMs => $composableBuilder(
    column: $table.profileMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get pressure => $composableBuilder(
    column: $table.pressure,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get flow => $composableBuilder(
    column: $table.flow,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get weight => $composableBuilder(
    column: $table.weight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get gravimetricFlow => $composableBuilder(
    column: $table.gravimetricFlow,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get externalTemp1 => $composableBuilder(
    column: $table.externalTemp1,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get externalTemp2 => $composableBuilder(
    column: $table.externalTemp2,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get barUp => $composableBuilder(
    column: $table.barUp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get barMidUp => $composableBuilder(
    column: $table.barMidUp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get barMidDown => $composableBuilder(
    column: $table.barMidDown,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get barDown => $composableBuilder(
    column: $table.barDown,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get tubeTemp => $composableBuilder(
    column: $table.tubeTemp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get motorTemp => $composableBuilder(
    column: $table.motorTemp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lamTemp => $composableBuilder(
    column: $table.lamTemp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get motorPosition => $composableBuilder(
    column: $table.motorPosition,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get motorSpeed => $composableBuilder(
    column: $table.motorSpeed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get motorPower => $composableBuilder(
    column: $table.motorPower,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get motorCurrent => $composableBuilder(
    column: $table.motorCurrent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bandheaterPower => $composableBuilder(
    column: $table.bandheaterPower,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bandheaterCurrent => $composableBuilder(
    column: $table.bandheaterCurrent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get pressureSensorRaw => $composableBuilder(
    column: $table.pressureSensorRaw,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get waterStatus => $composableBuilder(
    column: $table.waterStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get weightPrediction => $composableBuilder(
    column: $table.weightPrediction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stage => $composableBuilder(
    column: $table.stage,
    builder: (column) => ColumnFilters(column),
  );

  $$ShotsTableFilterComposer get shotId {
    final $$ShotsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shotId,
      referencedTable: $db.shots,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShotsTableFilterComposer(
            $db: $db,
            $table: $db.shots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ShotReadingsTableOrderingComposer
    extends Composer<_$AppDatabase, $ShotReadingsTable> {
  $$ShotReadingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timeMs => $composableBuilder(
    column: $table.timeMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get profileMs => $composableBuilder(
    column: $table.profileMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get pressure => $composableBuilder(
    column: $table.pressure,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get flow => $composableBuilder(
    column: $table.flow,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get weight => $composableBuilder(
    column: $table.weight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get gravimetricFlow => $composableBuilder(
    column: $table.gravimetricFlow,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get externalTemp1 => $composableBuilder(
    column: $table.externalTemp1,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get externalTemp2 => $composableBuilder(
    column: $table.externalTemp2,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get barUp => $composableBuilder(
    column: $table.barUp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get barMidUp => $composableBuilder(
    column: $table.barMidUp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get barMidDown => $composableBuilder(
    column: $table.barMidDown,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get barDown => $composableBuilder(
    column: $table.barDown,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get tubeTemp => $composableBuilder(
    column: $table.tubeTemp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get motorTemp => $composableBuilder(
    column: $table.motorTemp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lamTemp => $composableBuilder(
    column: $table.lamTemp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get motorPosition => $composableBuilder(
    column: $table.motorPosition,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get motorSpeed => $composableBuilder(
    column: $table.motorSpeed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get motorPower => $composableBuilder(
    column: $table.motorPower,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get motorCurrent => $composableBuilder(
    column: $table.motorCurrent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bandheaterPower => $composableBuilder(
    column: $table.bandheaterPower,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bandheaterCurrent => $composableBuilder(
    column: $table.bandheaterCurrent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get pressureSensorRaw => $composableBuilder(
    column: $table.pressureSensorRaw,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get waterStatus => $composableBuilder(
    column: $table.waterStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get weightPrediction => $composableBuilder(
    column: $table.weightPrediction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stage => $composableBuilder(
    column: $table.stage,
    builder: (column) => ColumnOrderings(column),
  );

  $$ShotsTableOrderingComposer get shotId {
    final $$ShotsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shotId,
      referencedTable: $db.shots,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShotsTableOrderingComposer(
            $db: $db,
            $table: $db.shots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ShotReadingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ShotReadingsTable> {
  $$ShotReadingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get timeMs =>
      $composableBuilder(column: $table.timeMs, builder: (column) => column);

  GeneratedColumn<int> get profileMs =>
      $composableBuilder(column: $table.profileMs, builder: (column) => column);

  GeneratedColumn<double> get pressure =>
      $composableBuilder(column: $table.pressure, builder: (column) => column);

  GeneratedColumn<double> get flow =>
      $composableBuilder(column: $table.flow, builder: (column) => column);

  GeneratedColumn<double> get weight =>
      $composableBuilder(column: $table.weight, builder: (column) => column);

  GeneratedColumn<double> get gravimetricFlow => $composableBuilder(
    column: $table.gravimetricFlow,
    builder: (column) => column,
  );

  GeneratedColumn<double> get externalTemp1 => $composableBuilder(
    column: $table.externalTemp1,
    builder: (column) => column,
  );

  GeneratedColumn<double> get externalTemp2 => $composableBuilder(
    column: $table.externalTemp2,
    builder: (column) => column,
  );

  GeneratedColumn<double> get barUp =>
      $composableBuilder(column: $table.barUp, builder: (column) => column);

  GeneratedColumn<double> get barMidUp =>
      $composableBuilder(column: $table.barMidUp, builder: (column) => column);

  GeneratedColumn<double> get barMidDown => $composableBuilder(
    column: $table.barMidDown,
    builder: (column) => column,
  );

  GeneratedColumn<double> get barDown =>
      $composableBuilder(column: $table.barDown, builder: (column) => column);

  GeneratedColumn<double> get tubeTemp =>
      $composableBuilder(column: $table.tubeTemp, builder: (column) => column);

  GeneratedColumn<double> get motorTemp =>
      $composableBuilder(column: $table.motorTemp, builder: (column) => column);

  GeneratedColumn<double> get lamTemp =>
      $composableBuilder(column: $table.lamTemp, builder: (column) => column);

  GeneratedColumn<double> get motorPosition => $composableBuilder(
    column: $table.motorPosition,
    builder: (column) => column,
  );

  GeneratedColumn<double> get motorSpeed => $composableBuilder(
    column: $table.motorSpeed,
    builder: (column) => column,
  );

  GeneratedColumn<double> get motorPower => $composableBuilder(
    column: $table.motorPower,
    builder: (column) => column,
  );

  GeneratedColumn<double> get motorCurrent => $composableBuilder(
    column: $table.motorCurrent,
    builder: (column) => column,
  );

  GeneratedColumn<double> get bandheaterPower => $composableBuilder(
    column: $table.bandheaterPower,
    builder: (column) => column,
  );

  GeneratedColumn<double> get bandheaterCurrent => $composableBuilder(
    column: $table.bandheaterCurrent,
    builder: (column) => column,
  );

  GeneratedColumn<double> get pressureSensorRaw => $composableBuilder(
    column: $table.pressureSensorRaw,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get waterStatus => $composableBuilder(
    column: $table.waterStatus,
    builder: (column) => column,
  );

  GeneratedColumn<double> get weightPrediction => $composableBuilder(
    column: $table.weightPrediction,
    builder: (column) => column,
  );

  GeneratedColumn<String> get stage =>
      $composableBuilder(column: $table.stage, builder: (column) => column);

  $$ShotsTableAnnotationComposer get shotId {
    final $$ShotsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shotId,
      referencedTable: $db.shots,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShotsTableAnnotationComposer(
            $db: $db,
            $table: $db.shots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ShotReadingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ShotReadingsTable,
          ShotReading,
          $$ShotReadingsTableFilterComposer,
          $$ShotReadingsTableOrderingComposer,
          $$ShotReadingsTableAnnotationComposer,
          $$ShotReadingsTableCreateCompanionBuilder,
          $$ShotReadingsTableUpdateCompanionBuilder,
          (ShotReading, $$ShotReadingsTableReferences),
          ShotReading,
          PrefetchHooks Function({bool shotId})
        > {
  $$ShotReadingsTableTableManager(_$AppDatabase db, $ShotReadingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ShotReadingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ShotReadingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ShotReadingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> shotId = const Value.absent(),
                Value<int> timeMs = const Value.absent(),
                Value<int?> profileMs = const Value.absent(),
                Value<double?> pressure = const Value.absent(),
                Value<double?> flow = const Value.absent(),
                Value<double?> weight = const Value.absent(),
                Value<double?> gravimetricFlow = const Value.absent(),
                Value<double?> externalTemp1 = const Value.absent(),
                Value<double?> externalTemp2 = const Value.absent(),
                Value<double?> barUp = const Value.absent(),
                Value<double?> barMidUp = const Value.absent(),
                Value<double?> barMidDown = const Value.absent(),
                Value<double?> barDown = const Value.absent(),
                Value<double?> tubeTemp = const Value.absent(),
                Value<double?> motorTemp = const Value.absent(),
                Value<double?> lamTemp = const Value.absent(),
                Value<double?> motorPosition = const Value.absent(),
                Value<double?> motorSpeed = const Value.absent(),
                Value<double?> motorPower = const Value.absent(),
                Value<double?> motorCurrent = const Value.absent(),
                Value<double?> bandheaterPower = const Value.absent(),
                Value<double?> bandheaterCurrent = const Value.absent(),
                Value<double?> pressureSensorRaw = const Value.absent(),
                Value<bool?> waterStatus = const Value.absent(),
                Value<double?> weightPrediction = const Value.absent(),
                Value<String?> stage = const Value.absent(),
              }) => ShotReadingsCompanion(
                id: id,
                shotId: shotId,
                timeMs: timeMs,
                profileMs: profileMs,
                pressure: pressure,
                flow: flow,
                weight: weight,
                gravimetricFlow: gravimetricFlow,
                externalTemp1: externalTemp1,
                externalTemp2: externalTemp2,
                barUp: barUp,
                barMidUp: barMidUp,
                barMidDown: barMidDown,
                barDown: barDown,
                tubeTemp: tubeTemp,
                motorTemp: motorTemp,
                lamTemp: lamTemp,
                motorPosition: motorPosition,
                motorSpeed: motorSpeed,
                motorPower: motorPower,
                motorCurrent: motorCurrent,
                bandheaterPower: bandheaterPower,
                bandheaterCurrent: bandheaterCurrent,
                pressureSensorRaw: pressureSensorRaw,
                waterStatus: waterStatus,
                weightPrediction: weightPrediction,
                stage: stage,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int shotId,
                required int timeMs,
                Value<int?> profileMs = const Value.absent(),
                Value<double?> pressure = const Value.absent(),
                Value<double?> flow = const Value.absent(),
                Value<double?> weight = const Value.absent(),
                Value<double?> gravimetricFlow = const Value.absent(),
                Value<double?> externalTemp1 = const Value.absent(),
                Value<double?> externalTemp2 = const Value.absent(),
                Value<double?> barUp = const Value.absent(),
                Value<double?> barMidUp = const Value.absent(),
                Value<double?> barMidDown = const Value.absent(),
                Value<double?> barDown = const Value.absent(),
                Value<double?> tubeTemp = const Value.absent(),
                Value<double?> motorTemp = const Value.absent(),
                Value<double?> lamTemp = const Value.absent(),
                Value<double?> motorPosition = const Value.absent(),
                Value<double?> motorSpeed = const Value.absent(),
                Value<double?> motorPower = const Value.absent(),
                Value<double?> motorCurrent = const Value.absent(),
                Value<double?> bandheaterPower = const Value.absent(),
                Value<double?> bandheaterCurrent = const Value.absent(),
                Value<double?> pressureSensorRaw = const Value.absent(),
                Value<bool?> waterStatus = const Value.absent(),
                Value<double?> weightPrediction = const Value.absent(),
                Value<String?> stage = const Value.absent(),
              }) => ShotReadingsCompanion.insert(
                id: id,
                shotId: shotId,
                timeMs: timeMs,
                profileMs: profileMs,
                pressure: pressure,
                flow: flow,
                weight: weight,
                gravimetricFlow: gravimetricFlow,
                externalTemp1: externalTemp1,
                externalTemp2: externalTemp2,
                barUp: barUp,
                barMidUp: barMidUp,
                barMidDown: barMidDown,
                barDown: barDown,
                tubeTemp: tubeTemp,
                motorTemp: motorTemp,
                lamTemp: lamTemp,
                motorPosition: motorPosition,
                motorSpeed: motorSpeed,
                motorPower: motorPower,
                motorCurrent: motorCurrent,
                bandheaterPower: bandheaterPower,
                bandheaterCurrent: bandheaterCurrent,
                pressureSensorRaw: pressureSensorRaw,
                waterStatus: waterStatus,
                weightPrediction: weightPrediction,
                stage: stage,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ShotReadingsTable, ShotReading>(table),
                  $$ShotReadingsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({shotId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (shotId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.shotId,
                        referencedTable: $$ShotReadingsTableReferences
                            ._shotIdTable(db),
                        referencedColumn: $$ShotReadingsTableReferences
                            ._shotIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ShotReadingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ShotReadingsTable,
      ShotReading,
      $$ShotReadingsTableFilterComposer,
      $$ShotReadingsTableOrderingComposer,
      $$ShotReadingsTableAnnotationComposer,
      $$ShotReadingsTableCreateCompanionBuilder,
      $$ShotReadingsTableUpdateCompanionBuilder,
      (ShotReading, $$ShotReadingsTableReferences),
      ShotReading,
      PrefetchHooks Function({bool shotId})
    >;
typedef $$StoredProfilesTableCreateCompanionBuilder =
    StoredProfilesCompanion Function({
      Value<String> syncId,
      Value<int> updatedAt,
      Value<String?> deviceId,
      Value<String> syncState,
      required String id,
      Value<String> machine,
      required String name,
      required String json,
      Value<String?> imagePath,
      Value<int> position,
      required DateTime fetchedAt,
      Value<String?> customDescription,
      Value<String?> customImagePath,
      Value<String?> customImageBlob,
      Value<bool> deleted,
      Value<int> rowid,
    });
typedef $$StoredProfilesTableUpdateCompanionBuilder =
    StoredProfilesCompanion Function({
      Value<String> syncId,
      Value<int> updatedAt,
      Value<String?> deviceId,
      Value<String> syncState,
      Value<String> id,
      Value<String> machine,
      Value<String> name,
      Value<String> json,
      Value<String?> imagePath,
      Value<int> position,
      Value<DateTime> fetchedAt,
      Value<String?> customDescription,
      Value<String?> customImagePath,
      Value<String?> customImageBlob,
      Value<bool> deleted,
      Value<int> rowid,
    });

class $$StoredProfilesTableFilterComposer
    extends Composer<_$AppDatabase, $StoredProfilesTable> {
  $$StoredProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get syncId => $composableBuilder(
    column: $table.syncId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get machine => $composableBuilder(
    column: $table.machine,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imagePath => $composableBuilder(
    column: $table.imagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customDescription => $composableBuilder(
    column: $table.customDescription,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customImagePath => $composableBuilder(
    column: $table.customImagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customImageBlob => $composableBuilder(
    column: $table.customImageBlob,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StoredProfilesTableOrderingComposer
    extends Composer<_$AppDatabase, $StoredProfilesTable> {
  $$StoredProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get syncId => $composableBuilder(
    column: $table.syncId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get machine => $composableBuilder(
    column: $table.machine,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imagePath => $composableBuilder(
    column: $table.imagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customDescription => $composableBuilder(
    column: $table.customDescription,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customImagePath => $composableBuilder(
    column: $table.customImagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customImageBlob => $composableBuilder(
    column: $table.customImageBlob,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StoredProfilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $StoredProfilesTable> {
  $$StoredProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get syncId =>
      $composableBuilder(column: $table.syncId, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get machine =>
      $composableBuilder(column: $table.machine, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<String> get imagePath =>
      $composableBuilder(column: $table.imagePath, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);

  GeneratedColumn<String> get customDescription => $composableBuilder(
    column: $table.customDescription,
    builder: (column) => column,
  );

  GeneratedColumn<String> get customImagePath => $composableBuilder(
    column: $table.customImagePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get customImageBlob => $composableBuilder(
    column: $table.customImageBlob,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);
}

class $$StoredProfilesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $StoredProfilesTable,
          StoredProfile,
          $$StoredProfilesTableFilterComposer,
          $$StoredProfilesTableOrderingComposer,
          $$StoredProfilesTableAnnotationComposer,
          $$StoredProfilesTableCreateCompanionBuilder,
          $$StoredProfilesTableUpdateCompanionBuilder,
          (
            StoredProfile,
            BaseReferences<_$AppDatabase, $StoredProfilesTable, StoredProfile>,
          ),
          StoredProfile,
          PrefetchHooks Function()
        > {
  $$StoredProfilesTableTableManager(
    _$AppDatabase db,
    $StoredProfilesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoredProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StoredProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StoredProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> syncId = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String?> deviceId = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> machine = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<String?> imagePath = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<String?> customDescription = const Value.absent(),
                Value<String?> customImagePath = const Value.absent(),
                Value<String?> customImageBlob = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StoredProfilesCompanion(
                syncId: syncId,
                updatedAt: updatedAt,
                deviceId: deviceId,
                syncState: syncState,
                id: id,
                machine: machine,
                name: name,
                json: json,
                imagePath: imagePath,
                position: position,
                fetchedAt: fetchedAt,
                customDescription: customDescription,
                customImagePath: customImagePath,
                customImageBlob: customImageBlob,
                deleted: deleted,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> syncId = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String?> deviceId = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                required String id,
                Value<String> machine = const Value.absent(),
                required String name,
                required String json,
                Value<String?> imagePath = const Value.absent(),
                Value<int> position = const Value.absent(),
                required DateTime fetchedAt,
                Value<String?> customDescription = const Value.absent(),
                Value<String?> customImagePath = const Value.absent(),
                Value<String?> customImageBlob = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StoredProfilesCompanion.insert(
                syncId: syncId,
                updatedAt: updatedAt,
                deviceId: deviceId,
                syncState: syncState,
                id: id,
                machine: machine,
                name: name,
                json: json,
                imagePath: imagePath,
                position: position,
                fetchedAt: fetchedAt,
                customDescription: customDescription,
                customImagePath: customImagePath,
                customImageBlob: customImageBlob,
                deleted: deleted,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$StoredProfilesTable, StoredProfile>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $StoredProfilesTable,
                    StoredProfile
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StoredProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $StoredProfilesTable,
      StoredProfile,
      $$StoredProfilesTableFilterComposer,
      $$StoredProfilesTableOrderingComposer,
      $$StoredProfilesTableAnnotationComposer,
      $$StoredProfilesTableCreateCompanionBuilder,
      $$StoredProfilesTableUpdateCompanionBuilder,
      (
        StoredProfile,
        BaseReferences<_$AppDatabase, $StoredProfilesTable, StoredProfile>,
      ),
      StoredProfile,
      PrefetchHooks Function()
    >;
typedef $$SyncedSettingsTableCreateCompanionBuilder =
    SyncedSettingsCompanion Function({
      Value<String> syncId,
      Value<int> updatedAt,
      Value<String?> deviceId,
      Value<String> syncState,
      required String key,
      Value<String?> value,
      Value<int> rowid,
    });
typedef $$SyncedSettingsTableUpdateCompanionBuilder =
    SyncedSettingsCompanion Function({
      Value<String> syncId,
      Value<int> updatedAt,
      Value<String?> deviceId,
      Value<String> syncState,
      Value<String> key,
      Value<String?> value,
      Value<int> rowid,
    });

class $$SyncedSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $SyncedSettingsTable> {
  $$SyncedSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get syncId => $composableBuilder(
    column: $table.syncId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncedSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncedSettingsTable> {
  $$SyncedSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get syncId => $composableBuilder(
    column: $table.syncId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncedSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncedSettingsTable> {
  $$SyncedSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get syncId =>
      $composableBuilder(column: $table.syncId, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);

  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SyncedSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncedSettingsTable,
          SyncedSetting,
          $$SyncedSettingsTableFilterComposer,
          $$SyncedSettingsTableOrderingComposer,
          $$SyncedSettingsTableAnnotationComposer,
          $$SyncedSettingsTableCreateCompanionBuilder,
          $$SyncedSettingsTableUpdateCompanionBuilder,
          (
            SyncedSetting,
            BaseReferences<_$AppDatabase, $SyncedSettingsTable, SyncedSetting>,
          ),
          SyncedSetting,
          PrefetchHooks Function()
        > {
  $$SyncedSettingsTableTableManager(
    _$AppDatabase db,
    $SyncedSettingsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncedSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncedSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncedSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> syncId = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String?> deviceId = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<String> key = const Value.absent(),
                Value<String?> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncedSettingsCompanion(
                syncId: syncId,
                updatedAt: updatedAt,
                deviceId: deviceId,
                syncState: syncState,
                key: key,
                value: value,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> syncId = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String?> deviceId = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                required String key,
                Value<String?> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncedSettingsCompanion.insert(
                syncId: syncId,
                updatedAt: updatedAt,
                deviceId: deviceId,
                syncState: syncState,
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncedSettingsTable, SyncedSetting>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SyncedSettingsTable,
                    SyncedSetting
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncedSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncedSettingsTable,
      SyncedSetting,
      $$SyncedSettingsTableFilterComposer,
      $$SyncedSettingsTableOrderingComposer,
      $$SyncedSettingsTableAnnotationComposer,
      $$SyncedSettingsTableCreateCompanionBuilder,
      $$SyncedSettingsTableUpdateCompanionBuilder,
      (
        SyncedSetting,
        BaseReferences<_$AppDatabase, $SyncedSettingsTable, SyncedSetting>,
      ),
      SyncedSetting,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$BeansTableTableManager get beans =>
      $$BeansTableTableManager(_db, _db.beans);
  $$ShotsTableTableManager get shots =>
      $$ShotsTableTableManager(_db, _db.shots);
  $$ShotReadingsTableTableManager get shotReadings =>
      $$ShotReadingsTableTableManager(_db, _db.shotReadings);
  $$StoredProfilesTableTableManager get storedProfiles =>
      $$StoredProfilesTableTableManager(_db, _db.storedProfiles);
  $$SyncedSettingsTableTableManager get syncedSettings =>
      $$SyncedSettingsTableTableManager(_db, _db.syncedSettings);
}
