// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $FieldsTable extends Fields with TableInfo<$FieldsTable, Field> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FieldsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  @override
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
    'lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lonMeta = const VerificationMeta('lon');
  @override
  late final GeneratedColumn<double> lon = GeneratedColumn<double>(
    'lon',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _areaHaMeta = const VerificationMeta('areaHa');
  @override
  late final GeneratedColumn<double> areaHa = GeneratedColumn<double>(
    'area_ha',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _districtMeta = const VerificationMeta(
    'district',
  );
  @override
  late final GeneratedColumn<String> district = GeneratedColumn<String>(
    'district',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sowingDateMeta = const VerificationMeta(
    'sowingDate',
  );
  @override
  late final GeneratedColumn<String> sowingDate = GeneratedColumn<String>(
    'sowing_date',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    lat,
    lon,
    areaHa,
    district,
    state,
    sowingDate,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'fields';
  @override
  VerificationContext validateIntegrity(
    Insertable<Field> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('lat')) {
      context.handle(
        _latMeta,
        lat.isAcceptableOrUnknown(data['lat']!, _latMeta),
      );
    } else if (isInserting) {
      context.missing(_latMeta);
    }
    if (data.containsKey('lon')) {
      context.handle(
        _lonMeta,
        lon.isAcceptableOrUnknown(data['lon']!, _lonMeta),
      );
    } else if (isInserting) {
      context.missing(_lonMeta);
    }
    if (data.containsKey('area_ha')) {
      context.handle(
        _areaHaMeta,
        areaHa.isAcceptableOrUnknown(data['area_ha']!, _areaHaMeta),
      );
    } else if (isInserting) {
      context.missing(_areaHaMeta);
    }
    if (data.containsKey('district')) {
      context.handle(
        _districtMeta,
        district.isAcceptableOrUnknown(data['district']!, _districtMeta),
      );
    } else if (isInserting) {
      context.missing(_districtMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('sowing_date')) {
      context.handle(
        _sowingDateMeta,
        sowingDate.isAcceptableOrUnknown(data['sowing_date']!, _sowingDateMeta),
      );
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Field map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Field(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      lat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lat'],
      )!,
      lon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lon'],
      )!,
      areaHa: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}area_ha'],
      )!,
      district: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}district'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      sowingDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sowing_date'],
      ),
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $FieldsTable createAlias(String alias) {
    return $FieldsTable(attachedDatabase, alias);
  }
}

class Field extends DataClass implements Insertable<Field> {
  final String id;
  final String name;
  final double lat;
  final double lon;
  final double areaHa;
  final String district;
  final String state;
  final String? sowingDate;
  final DateTime cachedAt;
  const Field({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.areaHa,
    required this.district,
    required this.state,
    this.sowingDate,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['lat'] = Variable<double>(lat);
    map['lon'] = Variable<double>(lon);
    map['area_ha'] = Variable<double>(areaHa);
    map['district'] = Variable<String>(district);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || sowingDate != null) {
      map['sowing_date'] = Variable<String>(sowingDate);
    }
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  FieldsCompanion toCompanion(bool nullToAbsent) {
    return FieldsCompanion(
      id: Value(id),
      name: Value(name),
      lat: Value(lat),
      lon: Value(lon),
      areaHa: Value(areaHa),
      district: Value(district),
      state: Value(state),
      sowingDate: sowingDate == null && nullToAbsent
          ? const Value.absent()
          : Value(sowingDate),
      cachedAt: Value(cachedAt),
    );
  }

  factory Field.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Field(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      lat: serializer.fromJson<double>(json['lat']),
      lon: serializer.fromJson<double>(json['lon']),
      areaHa: serializer.fromJson<double>(json['areaHa']),
      district: serializer.fromJson<String>(json['district']),
      state: serializer.fromJson<String>(json['state']),
      sowingDate: serializer.fromJson<String?>(json['sowingDate']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'lat': serializer.toJson<double>(lat),
      'lon': serializer.toJson<double>(lon),
      'areaHa': serializer.toJson<double>(areaHa),
      'district': serializer.toJson<String>(district),
      'state': serializer.toJson<String>(state),
      'sowingDate': serializer.toJson<String?>(sowingDate),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  Field copyWith({
    String? id,
    String? name,
    double? lat,
    double? lon,
    double? areaHa,
    String? district,
    String? state,
    Value<String?> sowingDate = const Value.absent(),
    DateTime? cachedAt,
  }) => Field(
    id: id ?? this.id,
    name: name ?? this.name,
    lat: lat ?? this.lat,
    lon: lon ?? this.lon,
    areaHa: areaHa ?? this.areaHa,
    district: district ?? this.district,
    state: state ?? this.state,
    sowingDate: sowingDate.present ? sowingDate.value : this.sowingDate,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  Field copyWithCompanion(FieldsCompanion data) {
    return Field(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      lat: data.lat.present ? data.lat.value : this.lat,
      lon: data.lon.present ? data.lon.value : this.lon,
      areaHa: data.areaHa.present ? data.areaHa.value : this.areaHa,
      district: data.district.present ? data.district.value : this.district,
      state: data.state.present ? data.state.value : this.state,
      sowingDate: data.sowingDate.present
          ? data.sowingDate.value
          : this.sowingDate,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Field(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('areaHa: $areaHa, ')
          ..write('district: $district, ')
          ..write('state: $state, ')
          ..write('sowingDate: $sowingDate, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    lat,
    lon,
    areaHa,
    district,
    state,
    sowingDate,
    cachedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Field &&
          other.id == this.id &&
          other.name == this.name &&
          other.lat == this.lat &&
          other.lon == this.lon &&
          other.areaHa == this.areaHa &&
          other.district == this.district &&
          other.state == this.state &&
          other.sowingDate == this.sowingDate &&
          other.cachedAt == this.cachedAt);
}

class FieldsCompanion extends UpdateCompanion<Field> {
  final Value<String> id;
  final Value<String> name;
  final Value<double> lat;
  final Value<double> lon;
  final Value<double> areaHa;
  final Value<String> district;
  final Value<String> state;
  final Value<String?> sowingDate;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const FieldsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.lat = const Value.absent(),
    this.lon = const Value.absent(),
    this.areaHa = const Value.absent(),
    this.district = const Value.absent(),
    this.state = const Value.absent(),
    this.sowingDate = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FieldsCompanion.insert({
    required String id,
    required String name,
    required double lat,
    required double lon,
    required double areaHa,
    required String district,
    required String state,
    this.sowingDate = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       lat = Value(lat),
       lon = Value(lon),
       areaHa = Value(areaHa),
       district = Value(district),
       state = Value(state);
  static Insertable<Field> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<double>? lat,
    Expression<double>? lon,
    Expression<double>? areaHa,
    Expression<String>? district,
    Expression<String>? state,
    Expression<String>? sowingDate,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (lat != null) 'lat': lat,
      if (lon != null) 'lon': lon,
      if (areaHa != null) 'area_ha': areaHa,
      if (district != null) 'district': district,
      if (state != null) 'state': state,
      if (sowingDate != null) 'sowing_date': sowingDate,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FieldsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<double>? lat,
    Value<double>? lon,
    Value<double>? areaHa,
    Value<String>? district,
    Value<String>? state,
    Value<String?>? sowingDate,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return FieldsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      areaHa: areaHa ?? this.areaHa,
      district: district ?? this.district,
      state: state ?? this.state,
      sowingDate: sowingDate ?? this.sowingDate,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lon.present) {
      map['lon'] = Variable<double>(lon.value);
    }
    if (areaHa.present) {
      map['area_ha'] = Variable<double>(areaHa.value);
    }
    if (district.present) {
      map['district'] = Variable<String>(district.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (sowingDate.present) {
      map['sowing_date'] = Variable<String>(sowingDate.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FieldsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('areaHa: $areaHa, ')
          ..write('district: $district, ')
          ..write('state: $state, ')
          ..write('sowingDate: $sowingDate, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlotsTable extends Plots with TableInfo<$PlotsTable, Plot> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fieldIdMeta = const VerificationMeta(
    'fieldId',
  );
  @override
  late final GeneratedColumn<String> fieldId = GeneratedColumn<String>(
    'field_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES fields (id)',
    ),
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _areaHaMeta = const VerificationMeta('areaHa');
  @override
  late final GeneratedColumn<double> areaHa = GeneratedColumn<double>(
    'area_ha',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, fieldId, label, areaHa];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'plots';
  @override
  VerificationContext validateIntegrity(
    Insertable<Plot> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('field_id')) {
      context.handle(
        _fieldIdMeta,
        fieldId.isAcceptableOrUnknown(data['field_id']!, _fieldIdMeta),
      );
    } else if (isInserting) {
      context.missing(_fieldIdMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('area_ha')) {
      context.handle(
        _areaHaMeta,
        areaHa.isAcceptableOrUnknown(data['area_ha']!, _areaHaMeta),
      );
    } else if (isInserting) {
      context.missing(_areaHaMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Plot map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Plot(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      fieldId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}field_id'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      areaHa: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}area_ha'],
      )!,
    );
  }

  @override
  $PlotsTable createAlias(String alias) {
    return $PlotsTable(attachedDatabase, alias);
  }
}

class Plot extends DataClass implements Insertable<Plot> {
  final String id;
  final String fieldId;
  final String label;
  final double areaHa;
  const Plot({
    required this.id,
    required this.fieldId,
    required this.label,
    required this.areaHa,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['field_id'] = Variable<String>(fieldId);
    map['label'] = Variable<String>(label);
    map['area_ha'] = Variable<double>(areaHa);
    return map;
  }

  PlotsCompanion toCompanion(bool nullToAbsent) {
    return PlotsCompanion(
      id: Value(id),
      fieldId: Value(fieldId),
      label: Value(label),
      areaHa: Value(areaHa),
    );
  }

  factory Plot.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Plot(
      id: serializer.fromJson<String>(json['id']),
      fieldId: serializer.fromJson<String>(json['fieldId']),
      label: serializer.fromJson<String>(json['label']),
      areaHa: serializer.fromJson<double>(json['areaHa']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'fieldId': serializer.toJson<String>(fieldId),
      'label': serializer.toJson<String>(label),
      'areaHa': serializer.toJson<double>(areaHa),
    };
  }

  Plot copyWith({String? id, String? fieldId, String? label, double? areaHa}) =>
      Plot(
        id: id ?? this.id,
        fieldId: fieldId ?? this.fieldId,
        label: label ?? this.label,
        areaHa: areaHa ?? this.areaHa,
      );
  Plot copyWithCompanion(PlotsCompanion data) {
    return Plot(
      id: data.id.present ? data.id.value : this.id,
      fieldId: data.fieldId.present ? data.fieldId.value : this.fieldId,
      label: data.label.present ? data.label.value : this.label,
      areaHa: data.areaHa.present ? data.areaHa.value : this.areaHa,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Plot(')
          ..write('id: $id, ')
          ..write('fieldId: $fieldId, ')
          ..write('label: $label, ')
          ..write('areaHa: $areaHa')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, fieldId, label, areaHa);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Plot &&
          other.id == this.id &&
          other.fieldId == this.fieldId &&
          other.label == this.label &&
          other.areaHa == this.areaHa);
}

class PlotsCompanion extends UpdateCompanion<Plot> {
  final Value<String> id;
  final Value<String> fieldId;
  final Value<String> label;
  final Value<double> areaHa;
  final Value<int> rowid;
  const PlotsCompanion({
    this.id = const Value.absent(),
    this.fieldId = const Value.absent(),
    this.label = const Value.absent(),
    this.areaHa = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlotsCompanion.insert({
    required String id,
    required String fieldId,
    required String label,
    required double areaHa,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       fieldId = Value(fieldId),
       label = Value(label),
       areaHa = Value(areaHa);
  static Insertable<Plot> custom({
    Expression<String>? id,
    Expression<String>? fieldId,
    Expression<String>? label,
    Expression<double>? areaHa,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (fieldId != null) 'field_id': fieldId,
      if (label != null) 'label': label,
      if (areaHa != null) 'area_ha': areaHa,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlotsCompanion copyWith({
    Value<String>? id,
    Value<String>? fieldId,
    Value<String>? label,
    Value<double>? areaHa,
    Value<int>? rowid,
  }) {
    return PlotsCompanion(
      id: id ?? this.id,
      fieldId: fieldId ?? this.fieldId,
      label: label ?? this.label,
      areaHa: areaHa ?? this.areaHa,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (fieldId.present) {
      map['field_id'] = Variable<String>(fieldId.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (areaHa.present) {
      map['area_ha'] = Variable<double>(areaHa.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlotsCompanion(')
          ..write('id: $id, ')
          ..write('fieldId: $fieldId, ')
          ..write('label: $label, ')
          ..write('areaHa: $areaHa, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CropPlansTable extends CropPlans
    with TableInfo<$CropPlansTable, CropPlan> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CropPlansTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _requestIdMeta = const VerificationMeta(
    'requestId',
  );
  @override
  late final GeneratedColumn<String> requestId = GeneratedColumn<String>(
    'request_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fieldIdMeta = const VerificationMeta(
    'fieldId',
  );
  @override
  late final GeneratedColumn<String> fieldId = GeneratedColumn<String>(
    'field_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES fields (id)',
    ),
  );
  static const VerificationMeta _solverMeta = const VerificationMeta('solver');
  @override
  late final GeneratedColumn<String> solver = GeneratedColumn<String>(
    'solver',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dataModeMeta = const VerificationMeta(
    'dataMode',
  );
  @override
  late final GeneratedColumn<String> dataMode = GeneratedColumn<String>(
    'data_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _netValueRsMeta = const VerificationMeta(
    'netValueRs',
  );
  @override
  late final GeneratedColumn<double> netValueRs = GeneratedColumn<double>(
    'net_value_rs',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _netValueP10RsMeta = const VerificationMeta(
    'netValueP10Rs',
  );
  @override
  late final GeneratedColumn<double> netValueP10Rs = GeneratedColumn<double>(
    'net_value_p10_rs',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _netValueP90RsMeta = const VerificationMeta(
    'netValueP90Rs',
  );
  @override
  late final GeneratedColumn<double> netValueP90Rs = GeneratedColumn<double>(
    'net_value_p90_rs',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _waterUsedM3Meta = const VerificationMeta(
    'waterUsedM3',
  );
  @override
  late final GeneratedColumn<double> waterUsedM3 = GeneratedColumn<double>(
    'water_used_m3',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _budgetUsedRsMeta = const VerificationMeta(
    'budgetUsedRs',
  );
  @override
  late final GeneratedColumn<double> budgetUsedRs = GeneratedColumn<double>(
    'budget_used_rs',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _benchmarkJsonMeta = const VerificationMeta(
    'benchmarkJson',
  );
  @override
  late final GeneratedColumn<String> benchmarkJson = GeneratedColumn<String>(
    'benchmark_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _advisoryJsonMeta = const VerificationMeta(
    'advisoryJson',
  );
  @override
  late final GeneratedColumn<String> advisoryJson = GeneratedColumn<String>(
    'advisory_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _alternativesJsonMeta = const VerificationMeta(
    'alternativesJson',
  );
  @override
  late final GeneratedColumn<String> alternativesJson = GeneratedColumn<String>(
    'alternatives_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    requestId,
    fieldId,
    solver,
    dataMode,
    netValueRs,
    netValueP10Rs,
    netValueP90Rs,
    waterUsedM3,
    budgetUsedRs,
    benchmarkJson,
    advisoryJson,
    alternativesJson,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'crop_plans';
  @override
  VerificationContext validateIntegrity(
    Insertable<CropPlan> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('request_id')) {
      context.handle(
        _requestIdMeta,
        requestId.isAcceptableOrUnknown(data['request_id']!, _requestIdMeta),
      );
    } else if (isInserting) {
      context.missing(_requestIdMeta);
    }
    if (data.containsKey('field_id')) {
      context.handle(
        _fieldIdMeta,
        fieldId.isAcceptableOrUnknown(data['field_id']!, _fieldIdMeta),
      );
    } else if (isInserting) {
      context.missing(_fieldIdMeta);
    }
    if (data.containsKey('solver')) {
      context.handle(
        _solverMeta,
        solver.isAcceptableOrUnknown(data['solver']!, _solverMeta),
      );
    } else if (isInserting) {
      context.missing(_solverMeta);
    }
    if (data.containsKey('data_mode')) {
      context.handle(
        _dataModeMeta,
        dataMode.isAcceptableOrUnknown(data['data_mode']!, _dataModeMeta),
      );
    } else if (isInserting) {
      context.missing(_dataModeMeta);
    }
    if (data.containsKey('net_value_rs')) {
      context.handle(
        _netValueRsMeta,
        netValueRs.isAcceptableOrUnknown(
          data['net_value_rs']!,
          _netValueRsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_netValueRsMeta);
    }
    if (data.containsKey('net_value_p10_rs')) {
      context.handle(
        _netValueP10RsMeta,
        netValueP10Rs.isAcceptableOrUnknown(
          data['net_value_p10_rs']!,
          _netValueP10RsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_netValueP10RsMeta);
    }
    if (data.containsKey('net_value_p90_rs')) {
      context.handle(
        _netValueP90RsMeta,
        netValueP90Rs.isAcceptableOrUnknown(
          data['net_value_p90_rs']!,
          _netValueP90RsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_netValueP90RsMeta);
    }
    if (data.containsKey('water_used_m3')) {
      context.handle(
        _waterUsedM3Meta,
        waterUsedM3.isAcceptableOrUnknown(
          data['water_used_m3']!,
          _waterUsedM3Meta,
        ),
      );
    } else if (isInserting) {
      context.missing(_waterUsedM3Meta);
    }
    if (data.containsKey('budget_used_rs')) {
      context.handle(
        _budgetUsedRsMeta,
        budgetUsedRs.isAcceptableOrUnknown(
          data['budget_used_rs']!,
          _budgetUsedRsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_budgetUsedRsMeta);
    }
    if (data.containsKey('benchmark_json')) {
      context.handle(
        _benchmarkJsonMeta,
        benchmarkJson.isAcceptableOrUnknown(
          data['benchmark_json']!,
          _benchmarkJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_benchmarkJsonMeta);
    }
    if (data.containsKey('advisory_json')) {
      context.handle(
        _advisoryJsonMeta,
        advisoryJson.isAcceptableOrUnknown(
          data['advisory_json']!,
          _advisoryJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_advisoryJsonMeta);
    }
    if (data.containsKey('alternatives_json')) {
      context.handle(
        _alternativesJsonMeta,
        alternativesJson.isAcceptableOrUnknown(
          data['alternatives_json']!,
          _alternativesJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_alternativesJsonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CropPlan map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CropPlan(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      requestId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}request_id'],
      )!,
      fieldId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}field_id'],
      )!,
      solver: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}solver'],
      )!,
      dataMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data_mode'],
      )!,
      netValueRs: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}net_value_rs'],
      )!,
      netValueP10Rs: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}net_value_p10_rs'],
      )!,
      netValueP90Rs: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}net_value_p90_rs'],
      )!,
      waterUsedM3: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}water_used_m3'],
      )!,
      budgetUsedRs: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}budget_used_rs'],
      )!,
      benchmarkJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}benchmark_json'],
      )!,
      advisoryJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}advisory_json'],
      )!,
      alternativesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}alternatives_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $CropPlansTable createAlias(String alias) {
    return $CropPlansTable(attachedDatabase, alias);
  }
}

class CropPlan extends DataClass implements Insertable<CropPlan> {
  final int id;
  final String requestId;
  final String fieldId;
  final String solver;
  final String dataMode;
  final double netValueRs;
  final double netValueP10Rs;
  final double netValueP90Rs;
  final double waterUsedM3;
  final double budgetUsedRs;
  final String benchmarkJson;
  final String advisoryJson;
  final String alternativesJson;
  final DateTime createdAt;
  const CropPlan({
    required this.id,
    required this.requestId,
    required this.fieldId,
    required this.solver,
    required this.dataMode,
    required this.netValueRs,
    required this.netValueP10Rs,
    required this.netValueP90Rs,
    required this.waterUsedM3,
    required this.budgetUsedRs,
    required this.benchmarkJson,
    required this.advisoryJson,
    required this.alternativesJson,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['request_id'] = Variable<String>(requestId);
    map['field_id'] = Variable<String>(fieldId);
    map['solver'] = Variable<String>(solver);
    map['data_mode'] = Variable<String>(dataMode);
    map['net_value_rs'] = Variable<double>(netValueRs);
    map['net_value_p10_rs'] = Variable<double>(netValueP10Rs);
    map['net_value_p90_rs'] = Variable<double>(netValueP90Rs);
    map['water_used_m3'] = Variable<double>(waterUsedM3);
    map['budget_used_rs'] = Variable<double>(budgetUsedRs);
    map['benchmark_json'] = Variable<String>(benchmarkJson);
    map['advisory_json'] = Variable<String>(advisoryJson);
    map['alternatives_json'] = Variable<String>(alternativesJson);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  CropPlansCompanion toCompanion(bool nullToAbsent) {
    return CropPlansCompanion(
      id: Value(id),
      requestId: Value(requestId),
      fieldId: Value(fieldId),
      solver: Value(solver),
      dataMode: Value(dataMode),
      netValueRs: Value(netValueRs),
      netValueP10Rs: Value(netValueP10Rs),
      netValueP90Rs: Value(netValueP90Rs),
      waterUsedM3: Value(waterUsedM3),
      budgetUsedRs: Value(budgetUsedRs),
      benchmarkJson: Value(benchmarkJson),
      advisoryJson: Value(advisoryJson),
      alternativesJson: Value(alternativesJson),
      createdAt: Value(createdAt),
    );
  }

  factory CropPlan.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CropPlan(
      id: serializer.fromJson<int>(json['id']),
      requestId: serializer.fromJson<String>(json['requestId']),
      fieldId: serializer.fromJson<String>(json['fieldId']),
      solver: serializer.fromJson<String>(json['solver']),
      dataMode: serializer.fromJson<String>(json['dataMode']),
      netValueRs: serializer.fromJson<double>(json['netValueRs']),
      netValueP10Rs: serializer.fromJson<double>(json['netValueP10Rs']),
      netValueP90Rs: serializer.fromJson<double>(json['netValueP90Rs']),
      waterUsedM3: serializer.fromJson<double>(json['waterUsedM3']),
      budgetUsedRs: serializer.fromJson<double>(json['budgetUsedRs']),
      benchmarkJson: serializer.fromJson<String>(json['benchmarkJson']),
      advisoryJson: serializer.fromJson<String>(json['advisoryJson']),
      alternativesJson: serializer.fromJson<String>(json['alternativesJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'requestId': serializer.toJson<String>(requestId),
      'fieldId': serializer.toJson<String>(fieldId),
      'solver': serializer.toJson<String>(solver),
      'dataMode': serializer.toJson<String>(dataMode),
      'netValueRs': serializer.toJson<double>(netValueRs),
      'netValueP10Rs': serializer.toJson<double>(netValueP10Rs),
      'netValueP90Rs': serializer.toJson<double>(netValueP90Rs),
      'waterUsedM3': serializer.toJson<double>(waterUsedM3),
      'budgetUsedRs': serializer.toJson<double>(budgetUsedRs),
      'benchmarkJson': serializer.toJson<String>(benchmarkJson),
      'advisoryJson': serializer.toJson<String>(advisoryJson),
      'alternativesJson': serializer.toJson<String>(alternativesJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  CropPlan copyWith({
    int? id,
    String? requestId,
    String? fieldId,
    String? solver,
    String? dataMode,
    double? netValueRs,
    double? netValueP10Rs,
    double? netValueP90Rs,
    double? waterUsedM3,
    double? budgetUsedRs,
    String? benchmarkJson,
    String? advisoryJson,
    String? alternativesJson,
    DateTime? createdAt,
  }) => CropPlan(
    id: id ?? this.id,
    requestId: requestId ?? this.requestId,
    fieldId: fieldId ?? this.fieldId,
    solver: solver ?? this.solver,
    dataMode: dataMode ?? this.dataMode,
    netValueRs: netValueRs ?? this.netValueRs,
    netValueP10Rs: netValueP10Rs ?? this.netValueP10Rs,
    netValueP90Rs: netValueP90Rs ?? this.netValueP90Rs,
    waterUsedM3: waterUsedM3 ?? this.waterUsedM3,
    budgetUsedRs: budgetUsedRs ?? this.budgetUsedRs,
    benchmarkJson: benchmarkJson ?? this.benchmarkJson,
    advisoryJson: advisoryJson ?? this.advisoryJson,
    alternativesJson: alternativesJson ?? this.alternativesJson,
    createdAt: createdAt ?? this.createdAt,
  );
  CropPlan copyWithCompanion(CropPlansCompanion data) {
    return CropPlan(
      id: data.id.present ? data.id.value : this.id,
      requestId: data.requestId.present ? data.requestId.value : this.requestId,
      fieldId: data.fieldId.present ? data.fieldId.value : this.fieldId,
      solver: data.solver.present ? data.solver.value : this.solver,
      dataMode: data.dataMode.present ? data.dataMode.value : this.dataMode,
      netValueRs: data.netValueRs.present
          ? data.netValueRs.value
          : this.netValueRs,
      netValueP10Rs: data.netValueP10Rs.present
          ? data.netValueP10Rs.value
          : this.netValueP10Rs,
      netValueP90Rs: data.netValueP90Rs.present
          ? data.netValueP90Rs.value
          : this.netValueP90Rs,
      waterUsedM3: data.waterUsedM3.present
          ? data.waterUsedM3.value
          : this.waterUsedM3,
      budgetUsedRs: data.budgetUsedRs.present
          ? data.budgetUsedRs.value
          : this.budgetUsedRs,
      benchmarkJson: data.benchmarkJson.present
          ? data.benchmarkJson.value
          : this.benchmarkJson,
      advisoryJson: data.advisoryJson.present
          ? data.advisoryJson.value
          : this.advisoryJson,
      alternativesJson: data.alternativesJson.present
          ? data.alternativesJson.value
          : this.alternativesJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CropPlan(')
          ..write('id: $id, ')
          ..write('requestId: $requestId, ')
          ..write('fieldId: $fieldId, ')
          ..write('solver: $solver, ')
          ..write('dataMode: $dataMode, ')
          ..write('netValueRs: $netValueRs, ')
          ..write('netValueP10Rs: $netValueP10Rs, ')
          ..write('netValueP90Rs: $netValueP90Rs, ')
          ..write('waterUsedM3: $waterUsedM3, ')
          ..write('budgetUsedRs: $budgetUsedRs, ')
          ..write('benchmarkJson: $benchmarkJson, ')
          ..write('advisoryJson: $advisoryJson, ')
          ..write('alternativesJson: $alternativesJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    requestId,
    fieldId,
    solver,
    dataMode,
    netValueRs,
    netValueP10Rs,
    netValueP90Rs,
    waterUsedM3,
    budgetUsedRs,
    benchmarkJson,
    advisoryJson,
    alternativesJson,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CropPlan &&
          other.id == this.id &&
          other.requestId == this.requestId &&
          other.fieldId == this.fieldId &&
          other.solver == this.solver &&
          other.dataMode == this.dataMode &&
          other.netValueRs == this.netValueRs &&
          other.netValueP10Rs == this.netValueP10Rs &&
          other.netValueP90Rs == this.netValueP90Rs &&
          other.waterUsedM3 == this.waterUsedM3 &&
          other.budgetUsedRs == this.budgetUsedRs &&
          other.benchmarkJson == this.benchmarkJson &&
          other.advisoryJson == this.advisoryJson &&
          other.alternativesJson == this.alternativesJson &&
          other.createdAt == this.createdAt);
}

class CropPlansCompanion extends UpdateCompanion<CropPlan> {
  final Value<int> id;
  final Value<String> requestId;
  final Value<String> fieldId;
  final Value<String> solver;
  final Value<String> dataMode;
  final Value<double> netValueRs;
  final Value<double> netValueP10Rs;
  final Value<double> netValueP90Rs;
  final Value<double> waterUsedM3;
  final Value<double> budgetUsedRs;
  final Value<String> benchmarkJson;
  final Value<String> advisoryJson;
  final Value<String> alternativesJson;
  final Value<DateTime> createdAt;
  const CropPlansCompanion({
    this.id = const Value.absent(),
    this.requestId = const Value.absent(),
    this.fieldId = const Value.absent(),
    this.solver = const Value.absent(),
    this.dataMode = const Value.absent(),
    this.netValueRs = const Value.absent(),
    this.netValueP10Rs = const Value.absent(),
    this.netValueP90Rs = const Value.absent(),
    this.waterUsedM3 = const Value.absent(),
    this.budgetUsedRs = const Value.absent(),
    this.benchmarkJson = const Value.absent(),
    this.advisoryJson = const Value.absent(),
    this.alternativesJson = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  CropPlansCompanion.insert({
    this.id = const Value.absent(),
    required String requestId,
    required String fieldId,
    required String solver,
    required String dataMode,
    required double netValueRs,
    required double netValueP10Rs,
    required double netValueP90Rs,
    required double waterUsedM3,
    required double budgetUsedRs,
    required String benchmarkJson,
    required String advisoryJson,
    required String alternativesJson,
    this.createdAt = const Value.absent(),
  }) : requestId = Value(requestId),
       fieldId = Value(fieldId),
       solver = Value(solver),
       dataMode = Value(dataMode),
       netValueRs = Value(netValueRs),
       netValueP10Rs = Value(netValueP10Rs),
       netValueP90Rs = Value(netValueP90Rs),
       waterUsedM3 = Value(waterUsedM3),
       budgetUsedRs = Value(budgetUsedRs),
       benchmarkJson = Value(benchmarkJson),
       advisoryJson = Value(advisoryJson),
       alternativesJson = Value(alternativesJson);
  static Insertable<CropPlan> custom({
    Expression<int>? id,
    Expression<String>? requestId,
    Expression<String>? fieldId,
    Expression<String>? solver,
    Expression<String>? dataMode,
    Expression<double>? netValueRs,
    Expression<double>? netValueP10Rs,
    Expression<double>? netValueP90Rs,
    Expression<double>? waterUsedM3,
    Expression<double>? budgetUsedRs,
    Expression<String>? benchmarkJson,
    Expression<String>? advisoryJson,
    Expression<String>? alternativesJson,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (requestId != null) 'request_id': requestId,
      if (fieldId != null) 'field_id': fieldId,
      if (solver != null) 'solver': solver,
      if (dataMode != null) 'data_mode': dataMode,
      if (netValueRs != null) 'net_value_rs': netValueRs,
      if (netValueP10Rs != null) 'net_value_p10_rs': netValueP10Rs,
      if (netValueP90Rs != null) 'net_value_p90_rs': netValueP90Rs,
      if (waterUsedM3 != null) 'water_used_m3': waterUsedM3,
      if (budgetUsedRs != null) 'budget_used_rs': budgetUsedRs,
      if (benchmarkJson != null) 'benchmark_json': benchmarkJson,
      if (advisoryJson != null) 'advisory_json': advisoryJson,
      if (alternativesJson != null) 'alternatives_json': alternativesJson,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  CropPlansCompanion copyWith({
    Value<int>? id,
    Value<String>? requestId,
    Value<String>? fieldId,
    Value<String>? solver,
    Value<String>? dataMode,
    Value<double>? netValueRs,
    Value<double>? netValueP10Rs,
    Value<double>? netValueP90Rs,
    Value<double>? waterUsedM3,
    Value<double>? budgetUsedRs,
    Value<String>? benchmarkJson,
    Value<String>? advisoryJson,
    Value<String>? alternativesJson,
    Value<DateTime>? createdAt,
  }) {
    return CropPlansCompanion(
      id: id ?? this.id,
      requestId: requestId ?? this.requestId,
      fieldId: fieldId ?? this.fieldId,
      solver: solver ?? this.solver,
      dataMode: dataMode ?? this.dataMode,
      netValueRs: netValueRs ?? this.netValueRs,
      netValueP10Rs: netValueP10Rs ?? this.netValueP10Rs,
      netValueP90Rs: netValueP90Rs ?? this.netValueP90Rs,
      waterUsedM3: waterUsedM3 ?? this.waterUsedM3,
      budgetUsedRs: budgetUsedRs ?? this.budgetUsedRs,
      benchmarkJson: benchmarkJson ?? this.benchmarkJson,
      advisoryJson: advisoryJson ?? this.advisoryJson,
      alternativesJson: alternativesJson ?? this.alternativesJson,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (requestId.present) {
      map['request_id'] = Variable<String>(requestId.value);
    }
    if (fieldId.present) {
      map['field_id'] = Variable<String>(fieldId.value);
    }
    if (solver.present) {
      map['solver'] = Variable<String>(solver.value);
    }
    if (dataMode.present) {
      map['data_mode'] = Variable<String>(dataMode.value);
    }
    if (netValueRs.present) {
      map['net_value_rs'] = Variable<double>(netValueRs.value);
    }
    if (netValueP10Rs.present) {
      map['net_value_p10_rs'] = Variable<double>(netValueP10Rs.value);
    }
    if (netValueP90Rs.present) {
      map['net_value_p90_rs'] = Variable<double>(netValueP90Rs.value);
    }
    if (waterUsedM3.present) {
      map['water_used_m3'] = Variable<double>(waterUsedM3.value);
    }
    if (budgetUsedRs.present) {
      map['budget_used_rs'] = Variable<double>(budgetUsedRs.value);
    }
    if (benchmarkJson.present) {
      map['benchmark_json'] = Variable<String>(benchmarkJson.value);
    }
    if (advisoryJson.present) {
      map['advisory_json'] = Variable<String>(advisoryJson.value);
    }
    if (alternativesJson.present) {
      map['alternatives_json'] = Variable<String>(alternativesJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CropPlansCompanion(')
          ..write('id: $id, ')
          ..write('requestId: $requestId, ')
          ..write('fieldId: $fieldId, ')
          ..write('solver: $solver, ')
          ..write('dataMode: $dataMode, ')
          ..write('netValueRs: $netValueRs, ')
          ..write('netValueP10Rs: $netValueP10Rs, ')
          ..write('netValueP90Rs: $netValueP90Rs, ')
          ..write('waterUsedM3: $waterUsedM3, ')
          ..write('budgetUsedRs: $budgetUsedRs, ')
          ..write('benchmarkJson: $benchmarkJson, ')
          ..write('advisoryJson: $advisoryJson, ')
          ..write('alternativesJson: $alternativesJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $PlanAssignmentsTable extends PlanAssignments
    with TableInfo<$PlanAssignmentsTable, PlanAssignment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlanAssignmentsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _planIdMeta = const VerificationMeta('planId');
  @override
  late final GeneratedColumn<int> planId = GeneratedColumn<int>(
    'plan_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES crop_plans (id)',
    ),
  );
  static const VerificationMeta _plotIdMeta = const VerificationMeta('plotId');
  @override
  late final GeneratedColumn<String> plotId = GeneratedColumn<String>(
    'plot_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cropMeta = const VerificationMeta('crop');
  @override
  late final GeneratedColumn<String> crop = GeneratedColumn<String>(
    'crop',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _yieldTHaMeta = const VerificationMeta(
    'yieldTHa',
  );
  @override
  late final GeneratedColumn<double> yieldTHa = GeneratedColumn<double>(
    'yield_t_ha',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _p10Meta = const VerificationMeta('p10');
  @override
  late final GeneratedColumn<double> p10 = GeneratedColumn<double>(
    'p10',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _p90Meta = const VerificationMeta('p90');
  @override
  late final GeneratedColumn<double> p90 = GeneratedColumn<double>(
    'p90',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    planId,
    plotId,
    crop,
    yieldTHa,
    p10,
    p90,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'plan_assignments';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlanAssignment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('plan_id')) {
      context.handle(
        _planIdMeta,
        planId.isAcceptableOrUnknown(data['plan_id']!, _planIdMeta),
      );
    } else if (isInserting) {
      context.missing(_planIdMeta);
    }
    if (data.containsKey('plot_id')) {
      context.handle(
        _plotIdMeta,
        plotId.isAcceptableOrUnknown(data['plot_id']!, _plotIdMeta),
      );
    } else if (isInserting) {
      context.missing(_plotIdMeta);
    }
    if (data.containsKey('crop')) {
      context.handle(
        _cropMeta,
        crop.isAcceptableOrUnknown(data['crop']!, _cropMeta),
      );
    } else if (isInserting) {
      context.missing(_cropMeta);
    }
    if (data.containsKey('yield_t_ha')) {
      context.handle(
        _yieldTHaMeta,
        yieldTHa.isAcceptableOrUnknown(data['yield_t_ha']!, _yieldTHaMeta),
      );
    } else if (isInserting) {
      context.missing(_yieldTHaMeta);
    }
    if (data.containsKey('p10')) {
      context.handle(
        _p10Meta,
        p10.isAcceptableOrUnknown(data['p10']!, _p10Meta),
      );
    } else if (isInserting) {
      context.missing(_p10Meta);
    }
    if (data.containsKey('p90')) {
      context.handle(
        _p90Meta,
        p90.isAcceptableOrUnknown(data['p90']!, _p90Meta),
      );
    } else if (isInserting) {
      context.missing(_p90Meta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlanAssignment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlanAssignment(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      planId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}plan_id'],
      )!,
      plotId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plot_id'],
      )!,
      crop: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}crop'],
      )!,
      yieldTHa: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}yield_t_ha'],
      )!,
      p10: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}p10'],
      )!,
      p90: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}p90'],
      )!,
    );
  }

  @override
  $PlanAssignmentsTable createAlias(String alias) {
    return $PlanAssignmentsTable(attachedDatabase, alias);
  }
}

class PlanAssignment extends DataClass implements Insertable<PlanAssignment> {
  final int id;
  final int planId;
  final String plotId;
  final String crop;
  final double yieldTHa;
  final double p10;
  final double p90;
  const PlanAssignment({
    required this.id,
    required this.planId,
    required this.plotId,
    required this.crop,
    required this.yieldTHa,
    required this.p10,
    required this.p90,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['plan_id'] = Variable<int>(planId);
    map['plot_id'] = Variable<String>(plotId);
    map['crop'] = Variable<String>(crop);
    map['yield_t_ha'] = Variable<double>(yieldTHa);
    map['p10'] = Variable<double>(p10);
    map['p90'] = Variable<double>(p90);
    return map;
  }

  PlanAssignmentsCompanion toCompanion(bool nullToAbsent) {
    return PlanAssignmentsCompanion(
      id: Value(id),
      planId: Value(planId),
      plotId: Value(plotId),
      crop: Value(crop),
      yieldTHa: Value(yieldTHa),
      p10: Value(p10),
      p90: Value(p90),
    );
  }

  factory PlanAssignment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlanAssignment(
      id: serializer.fromJson<int>(json['id']),
      planId: serializer.fromJson<int>(json['planId']),
      plotId: serializer.fromJson<String>(json['plotId']),
      crop: serializer.fromJson<String>(json['crop']),
      yieldTHa: serializer.fromJson<double>(json['yieldTHa']),
      p10: serializer.fromJson<double>(json['p10']),
      p90: serializer.fromJson<double>(json['p90']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'planId': serializer.toJson<int>(planId),
      'plotId': serializer.toJson<String>(plotId),
      'crop': serializer.toJson<String>(crop),
      'yieldTHa': serializer.toJson<double>(yieldTHa),
      'p10': serializer.toJson<double>(p10),
      'p90': serializer.toJson<double>(p90),
    };
  }

  PlanAssignment copyWith({
    int? id,
    int? planId,
    String? plotId,
    String? crop,
    double? yieldTHa,
    double? p10,
    double? p90,
  }) => PlanAssignment(
    id: id ?? this.id,
    planId: planId ?? this.planId,
    plotId: plotId ?? this.plotId,
    crop: crop ?? this.crop,
    yieldTHa: yieldTHa ?? this.yieldTHa,
    p10: p10 ?? this.p10,
    p90: p90 ?? this.p90,
  );
  PlanAssignment copyWithCompanion(PlanAssignmentsCompanion data) {
    return PlanAssignment(
      id: data.id.present ? data.id.value : this.id,
      planId: data.planId.present ? data.planId.value : this.planId,
      plotId: data.plotId.present ? data.plotId.value : this.plotId,
      crop: data.crop.present ? data.crop.value : this.crop,
      yieldTHa: data.yieldTHa.present ? data.yieldTHa.value : this.yieldTHa,
      p10: data.p10.present ? data.p10.value : this.p10,
      p90: data.p90.present ? data.p90.value : this.p90,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlanAssignment(')
          ..write('id: $id, ')
          ..write('planId: $planId, ')
          ..write('plotId: $plotId, ')
          ..write('crop: $crop, ')
          ..write('yieldTHa: $yieldTHa, ')
          ..write('p10: $p10, ')
          ..write('p90: $p90')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, planId, plotId, crop, yieldTHa, p10, p90);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlanAssignment &&
          other.id == this.id &&
          other.planId == this.planId &&
          other.plotId == this.plotId &&
          other.crop == this.crop &&
          other.yieldTHa == this.yieldTHa &&
          other.p10 == this.p10 &&
          other.p90 == this.p90);
}

class PlanAssignmentsCompanion extends UpdateCompanion<PlanAssignment> {
  final Value<int> id;
  final Value<int> planId;
  final Value<String> plotId;
  final Value<String> crop;
  final Value<double> yieldTHa;
  final Value<double> p10;
  final Value<double> p90;
  const PlanAssignmentsCompanion({
    this.id = const Value.absent(),
    this.planId = const Value.absent(),
    this.plotId = const Value.absent(),
    this.crop = const Value.absent(),
    this.yieldTHa = const Value.absent(),
    this.p10 = const Value.absent(),
    this.p90 = const Value.absent(),
  });
  PlanAssignmentsCompanion.insert({
    this.id = const Value.absent(),
    required int planId,
    required String plotId,
    required String crop,
    required double yieldTHa,
    required double p10,
    required double p90,
  }) : planId = Value(planId),
       plotId = Value(plotId),
       crop = Value(crop),
       yieldTHa = Value(yieldTHa),
       p10 = Value(p10),
       p90 = Value(p90);
  static Insertable<PlanAssignment> custom({
    Expression<int>? id,
    Expression<int>? planId,
    Expression<String>? plotId,
    Expression<String>? crop,
    Expression<double>? yieldTHa,
    Expression<double>? p10,
    Expression<double>? p90,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (planId != null) 'plan_id': planId,
      if (plotId != null) 'plot_id': plotId,
      if (crop != null) 'crop': crop,
      if (yieldTHa != null) 'yield_t_ha': yieldTHa,
      if (p10 != null) 'p10': p10,
      if (p90 != null) 'p90': p90,
    });
  }

  PlanAssignmentsCompanion copyWith({
    Value<int>? id,
    Value<int>? planId,
    Value<String>? plotId,
    Value<String>? crop,
    Value<double>? yieldTHa,
    Value<double>? p10,
    Value<double>? p90,
  }) {
    return PlanAssignmentsCompanion(
      id: id ?? this.id,
      planId: planId ?? this.planId,
      plotId: plotId ?? this.plotId,
      crop: crop ?? this.crop,
      yieldTHa: yieldTHa ?? this.yieldTHa,
      p10: p10 ?? this.p10,
      p90: p90 ?? this.p90,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (planId.present) {
      map['plan_id'] = Variable<int>(planId.value);
    }
    if (plotId.present) {
      map['plot_id'] = Variable<String>(plotId.value);
    }
    if (crop.present) {
      map['crop'] = Variable<String>(crop.value);
    }
    if (yieldTHa.present) {
      map['yield_t_ha'] = Variable<double>(yieldTHa.value);
    }
    if (p10.present) {
      map['p10'] = Variable<double>(p10.value);
    }
    if (p90.present) {
      map['p90'] = Variable<double>(p90.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlanAssignmentsCompanion(')
          ..write('id: $id, ')
          ..write('planId: $planId, ')
          ..write('plotId: $plotId, ')
          ..write('crop: $crop, ')
          ..write('yieldTHa: $yieldTHa, ')
          ..write('p10: $p10, ')
          ..write('p90: $p90')
          ..write(')'))
        .toString();
  }
}

class $SyncQueueItemsTable extends SyncQueueItems
    with TableInfo<$SyncQueueItemsTable, SyncQueueItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncQueueItemsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncOpStatus, int> status =
      GeneratedColumn<int>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<SyncOpStatus>($SyncQueueItemsTable.$converterstatus);
  static const VerificationMeta _errorMessageMeta = const VerificationMeta(
    'errorMessage',
  );
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
    'error_message',
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
  static const VerificationMeta _lastAttemptAtMeta = const VerificationMeta(
    'lastAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastAttemptAt =
      GeneratedColumn<DateTime>(
        'last_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    payloadJson,
    status,
    errorMessage,
    createdAt,
    lastAttemptAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_queue_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncQueueItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('error_message')) {
      context.handle(
        _errorMessageMeta,
        errorMessage.isAcceptableOrUnknown(
          data['error_message']!,
          _errorMessageMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('last_attempt_at')) {
      context.handle(
        _lastAttemptAtMeta,
        lastAttemptAt.isAcceptableOrUnknown(
          data['last_attempt_at']!,
          _lastAttemptAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncQueueItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncQueueItem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      status: $SyncQueueItemsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}status'],
        )!,
      ),
      errorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_message'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      lastAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_attempt_at'],
      ),
    );
  }

  @override
  $SyncQueueItemsTable createAlias(String alias) {
    return $SyncQueueItemsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<SyncOpStatus, int, int> $converterstatus =
      const EnumIndexConverter<SyncOpStatus>(SyncOpStatus.values);
}

class SyncQueueItem extends DataClass implements Insertable<SyncQueueItem> {
  final int id;
  final String kind;
  final String payloadJson;
  final SyncOpStatus status;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime? lastAttemptAt;
  const SyncQueueItem({
    required this.id,
    required this.kind,
    required this.payloadJson,
    required this.status,
    this.errorMessage,
    required this.createdAt,
    this.lastAttemptAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['kind'] = Variable<String>(kind);
    map['payload_json'] = Variable<String>(payloadJson);
    {
      map['status'] = Variable<int>(
        $SyncQueueItemsTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || errorMessage != null) {
      map['error_message'] = Variable<String>(errorMessage);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || lastAttemptAt != null) {
      map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt);
    }
    return map;
  }

  SyncQueueItemsCompanion toCompanion(bool nullToAbsent) {
    return SyncQueueItemsCompanion(
      id: Value(id),
      kind: Value(kind),
      payloadJson: Value(payloadJson),
      status: Value(status),
      errorMessage: errorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(errorMessage),
      createdAt: Value(createdAt),
      lastAttemptAt: lastAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAttemptAt),
    );
  }

  factory SyncQueueItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncQueueItem(
      id: serializer.fromJson<int>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      status: $SyncQueueItemsTable.$converterstatus.fromJson(
        serializer.fromJson<int>(json['status']),
      ),
      errorMessage: serializer.fromJson<String?>(json['errorMessage']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      lastAttemptAt: serializer.fromJson<DateTime?>(json['lastAttemptAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'kind': serializer.toJson<String>(kind),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'status': serializer.toJson<int>(
        $SyncQueueItemsTable.$converterstatus.toJson(status),
      ),
      'errorMessage': serializer.toJson<String?>(errorMessage),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'lastAttemptAt': serializer.toJson<DateTime?>(lastAttemptAt),
    };
  }

  SyncQueueItem copyWith({
    int? id,
    String? kind,
    String? payloadJson,
    SyncOpStatus? status,
    Value<String?> errorMessage = const Value.absent(),
    DateTime? createdAt,
    Value<DateTime?> lastAttemptAt = const Value.absent(),
  }) => SyncQueueItem(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    payloadJson: payloadJson ?? this.payloadJson,
    status: status ?? this.status,
    errorMessage: errorMessage.present ? errorMessage.value : this.errorMessage,
    createdAt: createdAt ?? this.createdAt,
    lastAttemptAt: lastAttemptAt.present
        ? lastAttemptAt.value
        : this.lastAttemptAt,
  );
  SyncQueueItem copyWithCompanion(SyncQueueItemsCompanion data) {
    return SyncQueueItem(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      status: data.status.present ? data.status.value : this.status,
      errorMessage: data.errorMessage.present
          ? data.errorMessage.value
          : this.errorMessage,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastAttemptAt: data.lastAttemptAt.present
          ? data.lastAttemptAt.value
          : this.lastAttemptAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncQueueItem(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('status: $status, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastAttemptAt: $lastAttemptAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    payloadJson,
    status,
    errorMessage,
    createdAt,
    lastAttemptAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncQueueItem &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.payloadJson == this.payloadJson &&
          other.status == this.status &&
          other.errorMessage == this.errorMessage &&
          other.createdAt == this.createdAt &&
          other.lastAttemptAt == this.lastAttemptAt);
}

class SyncQueueItemsCompanion extends UpdateCompanion<SyncQueueItem> {
  final Value<int> id;
  final Value<String> kind;
  final Value<String> payloadJson;
  final Value<SyncOpStatus> status;
  final Value<String?> errorMessage;
  final Value<DateTime> createdAt;
  final Value<DateTime?> lastAttemptAt;
  const SyncQueueItemsCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.status = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
  });
  SyncQueueItemsCompanion.insert({
    this.id = const Value.absent(),
    required String kind,
    required String payloadJson,
    required SyncOpStatus status,
    this.errorMessage = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
  }) : kind = Value(kind),
       payloadJson = Value(payloadJson),
       status = Value(status);
  static Insertable<SyncQueueItem> custom({
    Expression<int>? id,
    Expression<String>? kind,
    Expression<String>? payloadJson,
    Expression<int>? status,
    Expression<String>? errorMessage,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? lastAttemptAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (status != null) 'status': status,
      if (errorMessage != null) 'error_message': errorMessage,
      if (createdAt != null) 'created_at': createdAt,
      if (lastAttemptAt != null) 'last_attempt_at': lastAttemptAt,
    });
  }

  SyncQueueItemsCompanion copyWith({
    Value<int>? id,
    Value<String>? kind,
    Value<String>? payloadJson,
    Value<SyncOpStatus>? status,
    Value<String?>? errorMessage,
    Value<DateTime>? createdAt,
    Value<DateTime?>? lastAttemptAt,
  }) {
    return SyncQueueItemsCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      payloadJson: payloadJson ?? this.payloadJson,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(
        $SyncQueueItemsTable.$converterstatus.toSql(status.value),
      );
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (lastAttemptAt.present) {
      map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncQueueItemsCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('status: $status, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastAttemptAt: $lastAttemptAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $FieldsTable fields = $FieldsTable(this);
  late final $PlotsTable plots = $PlotsTable(this);
  late final $CropPlansTable cropPlans = $CropPlansTable(this);
  late final $PlanAssignmentsTable planAssignments = $PlanAssignmentsTable(
    this,
  );
  late final $SyncQueueItemsTable syncQueueItems = $SyncQueueItemsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    fields,
    plots,
    cropPlans,
    planAssignments,
    syncQueueItems,
  ];
}

typedef $$FieldsTableCreateCompanionBuilder =
    FieldsCompanion Function({
      required String id,
      required String name,
      required double lat,
      required double lon,
      required double areaHa,
      required String district,
      required String state,
      Value<String?> sowingDate,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });
typedef $$FieldsTableUpdateCompanionBuilder =
    FieldsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<double> lat,
      Value<double> lon,
      Value<double> areaHa,
      Value<String> district,
      Value<String> state,
      Value<String?> sowingDate,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

final class $$FieldsTableReferences
    extends BaseReferences<_$AppDatabase, $FieldsTable, Field> {
  $$FieldsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$PlotsTable, List<Plot>> _plotsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.plots,
    aliasName: 'fields__id__plots__field_id',
  );

  $$PlotsTableProcessedTableManager get plotsRefs {
    final manager = $$PlotsTableTableManager(
      $_db,
      $_db.plots,
    ).filter((f) => f.fieldId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_plotsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$CropPlansTable, List<CropPlan>>
  _cropPlansRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.cropPlans,
    aliasName: 'fields__id__crop_plans__field_id',
  );

  $$CropPlansTableProcessedTableManager get cropPlansRefs {
    final manager = $$CropPlansTableTableManager(
      $_db,
      $_db.cropPlans,
    ).filter((f) => f.fieldId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_cropPlansRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$FieldsTableFilterComposer
    extends Composer<_$AppDatabase, $FieldsTable> {
  $$FieldsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lon => $composableBuilder(
    column: $table.lon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get areaHa => $composableBuilder(
    column: $table.areaHa,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get district => $composableBuilder(
    column: $table.district,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sowingDate => $composableBuilder(
    column: $table.sowingDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> plotsRefs(
    Expression<bool> Function($$PlotsTableFilterComposer f) f,
  ) {
    final $$PlotsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.plots,
      getReferencedColumn: (t) => t.fieldId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlotsTableFilterComposer(
            $db: $db,
            $table: $db.plots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> cropPlansRefs(
    Expression<bool> Function($$CropPlansTableFilterComposer f) f,
  ) {
    final $$CropPlansTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.cropPlans,
      getReferencedColumn: (t) => t.fieldId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CropPlansTableFilterComposer(
            $db: $db,
            $table: $db.cropPlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FieldsTableOrderingComposer
    extends Composer<_$AppDatabase, $FieldsTable> {
  $$FieldsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lon => $composableBuilder(
    column: $table.lon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get areaHa => $composableBuilder(
    column: $table.areaHa,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get district => $composableBuilder(
    column: $table.district,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sowingDate => $composableBuilder(
    column: $table.sowingDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FieldsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FieldsTable> {
  $$FieldsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<double> get lat =>
      $composableBuilder(column: $table.lat, builder: (column) => column);

  GeneratedColumn<double> get lon =>
      $composableBuilder(column: $table.lon, builder: (column) => column);

  GeneratedColumn<double> get areaHa =>
      $composableBuilder(column: $table.areaHa, builder: (column) => column);

  GeneratedColumn<String> get district =>
      $composableBuilder(column: $table.district, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get sowingDate => $composableBuilder(
    column: $table.sowingDate,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);

  Expression<T> plotsRefs<T extends Object>(
    Expression<T> Function($$PlotsTableAnnotationComposer a) f,
  ) {
    final $$PlotsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.plots,
      getReferencedColumn: (t) => t.fieldId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlotsTableAnnotationComposer(
            $db: $db,
            $table: $db.plots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> cropPlansRefs<T extends Object>(
    Expression<T> Function($$CropPlansTableAnnotationComposer a) f,
  ) {
    final $$CropPlansTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.cropPlans,
      getReferencedColumn: (t) => t.fieldId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CropPlansTableAnnotationComposer(
            $db: $db,
            $table: $db.cropPlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FieldsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FieldsTable,
          Field,
          $$FieldsTableFilterComposer,
          $$FieldsTableOrderingComposer,
          $$FieldsTableAnnotationComposer,
          $$FieldsTableCreateCompanionBuilder,
          $$FieldsTableUpdateCompanionBuilder,
          (Field, $$FieldsTableReferences),
          Field,
          PrefetchHooks Function({bool plotsRefs, bool cropPlansRefs})
        > {
  $$FieldsTableTableManager(_$AppDatabase db, $FieldsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FieldsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FieldsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FieldsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<double> lat = const Value.absent(),
                Value<double> lon = const Value.absent(),
                Value<double> areaHa = const Value.absent(),
                Value<String> district = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> sowingDate = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FieldsCompanion(
                id: id,
                name: name,
                lat: lat,
                lon: lon,
                areaHa: areaHa,
                district: district,
                state: state,
                sowingDate: sowingDate,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required double lat,
                required double lon,
                required double areaHa,
                required String district,
                required String state,
                Value<String?> sowingDate = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FieldsCompanion.insert(
                id: id,
                name: name,
                lat: lat,
                lon: lon,
                areaHa: areaHa,
                district: district,
                state: state,
                sowingDate: sowingDate,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$FieldsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({plotsRefs = false, cropPlansRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (plotsRefs) db.plots,
                if (cropPlansRefs) db.cropPlans,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (plotsRefs)
                    await $_getPrefetchedData<Field, $FieldsTable, Plot>(
                      currentTable: table,
                      referencedTable: $$FieldsTableReferences._plotsRefsTable(
                        db,
                      ),
                      managerFromTypedResult: (p0) =>
                          $$FieldsTableReferences(db, table, p0).plotsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.fieldId == item.id),
                      typedResults: items,
                    ),
                  if (cropPlansRefs)
                    await $_getPrefetchedData<Field, $FieldsTable, CropPlan>(
                      currentTable: table,
                      referencedTable: $$FieldsTableReferences
                          ._cropPlansRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$FieldsTableReferences(db, table, p0).cropPlansRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.fieldId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$FieldsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FieldsTable,
      Field,
      $$FieldsTableFilterComposer,
      $$FieldsTableOrderingComposer,
      $$FieldsTableAnnotationComposer,
      $$FieldsTableCreateCompanionBuilder,
      $$FieldsTableUpdateCompanionBuilder,
      (Field, $$FieldsTableReferences),
      Field,
      PrefetchHooks Function({bool plotsRefs, bool cropPlansRefs})
    >;
typedef $$PlotsTableCreateCompanionBuilder =
    PlotsCompanion Function({
      required String id,
      required String fieldId,
      required String label,
      required double areaHa,
      Value<int> rowid,
    });
typedef $$PlotsTableUpdateCompanionBuilder =
    PlotsCompanion Function({
      Value<String> id,
      Value<String> fieldId,
      Value<String> label,
      Value<double> areaHa,
      Value<int> rowid,
    });

final class $$PlotsTableReferences
    extends BaseReferences<_$AppDatabase, $PlotsTable, Plot> {
  $$PlotsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $FieldsTable _fieldIdTable(_$AppDatabase db) =>
      db.fields.createAlias('plots__field_id__fields__id');

  $$FieldsTableProcessedTableManager get fieldId {
    final $_column = $_itemColumn<String>('field_id')!;

    final manager = $$FieldsTableTableManager(
      $_db,
      $_db.fields,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_fieldIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PlotsTableFilterComposer extends Composer<_$AppDatabase, $PlotsTable> {
  $$PlotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get areaHa => $composableBuilder(
    column: $table.areaHa,
    builder: (column) => ColumnFilters(column),
  );

  $$FieldsTableFilterComposer get fieldId {
    final $$FieldsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fieldId,
      referencedTable: $db.fields,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FieldsTableFilterComposer(
            $db: $db,
            $table: $db.fields,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlotsTableOrderingComposer
    extends Composer<_$AppDatabase, $PlotsTable> {
  $$PlotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get areaHa => $composableBuilder(
    column: $table.areaHa,
    builder: (column) => ColumnOrderings(column),
  );

  $$FieldsTableOrderingComposer get fieldId {
    final $$FieldsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fieldId,
      referencedTable: $db.fields,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FieldsTableOrderingComposer(
            $db: $db,
            $table: $db.fields,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlotsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlotsTable> {
  $$PlotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<double> get areaHa =>
      $composableBuilder(column: $table.areaHa, builder: (column) => column);

  $$FieldsTableAnnotationComposer get fieldId {
    final $$FieldsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fieldId,
      referencedTable: $db.fields,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FieldsTableAnnotationComposer(
            $db: $db,
            $table: $db.fields,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlotsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlotsTable,
          Plot,
          $$PlotsTableFilterComposer,
          $$PlotsTableOrderingComposer,
          $$PlotsTableAnnotationComposer,
          $$PlotsTableCreateCompanionBuilder,
          $$PlotsTableUpdateCompanionBuilder,
          (Plot, $$PlotsTableReferences),
          Plot,
          PrefetchHooks Function({bool fieldId})
        > {
  $$PlotsTableTableManager(_$AppDatabase db, $PlotsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlotsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlotsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlotsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> fieldId = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<double> areaHa = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlotsCompanion(
                id: id,
                fieldId: fieldId,
                label: label,
                areaHa: areaHa,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String fieldId,
                required String label,
                required double areaHa,
                Value<int> rowid = const Value.absent(),
              }) => PlotsCompanion.insert(
                id: id,
                fieldId: fieldId,
                label: label,
                areaHa: areaHa,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$PlotsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({fieldId = false}) {
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
                    if (fieldId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.fieldId,
                                referencedTable: $$PlotsTableReferences
                                    ._fieldIdTable(db),
                                referencedColumn: $$PlotsTableReferences
                                    ._fieldIdTable(db)
                                    .id,
                              )
                              as T;
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

typedef $$PlotsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlotsTable,
      Plot,
      $$PlotsTableFilterComposer,
      $$PlotsTableOrderingComposer,
      $$PlotsTableAnnotationComposer,
      $$PlotsTableCreateCompanionBuilder,
      $$PlotsTableUpdateCompanionBuilder,
      (Plot, $$PlotsTableReferences),
      Plot,
      PrefetchHooks Function({bool fieldId})
    >;
typedef $$CropPlansTableCreateCompanionBuilder =
    CropPlansCompanion Function({
      Value<int> id,
      required String requestId,
      required String fieldId,
      required String solver,
      required String dataMode,
      required double netValueRs,
      required double netValueP10Rs,
      required double netValueP90Rs,
      required double waterUsedM3,
      required double budgetUsedRs,
      required String benchmarkJson,
      required String advisoryJson,
      required String alternativesJson,
      Value<DateTime> createdAt,
    });
typedef $$CropPlansTableUpdateCompanionBuilder =
    CropPlansCompanion Function({
      Value<int> id,
      Value<String> requestId,
      Value<String> fieldId,
      Value<String> solver,
      Value<String> dataMode,
      Value<double> netValueRs,
      Value<double> netValueP10Rs,
      Value<double> netValueP90Rs,
      Value<double> waterUsedM3,
      Value<double> budgetUsedRs,
      Value<String> benchmarkJson,
      Value<String> advisoryJson,
      Value<String> alternativesJson,
      Value<DateTime> createdAt,
    });

final class $$CropPlansTableReferences
    extends BaseReferences<_$AppDatabase, $CropPlansTable, CropPlan> {
  $$CropPlansTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $FieldsTable _fieldIdTable(_$AppDatabase db) =>
      db.fields.createAlias('crop_plans__field_id__fields__id');

  $$FieldsTableProcessedTableManager get fieldId {
    final $_column = $_itemColumn<String>('field_id')!;

    final manager = $$FieldsTableTableManager(
      $_db,
      $_db.fields,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_fieldIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$PlanAssignmentsTable, List<PlanAssignment>>
  _planAssignmentsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.planAssignments,
    aliasName: 'crop_plans__id__plan_assignments__plan_id',
  );

  $$PlanAssignmentsTableProcessedTableManager get planAssignmentsRefs {
    final manager = $$PlanAssignmentsTableTableManager(
      $_db,
      $_db.planAssignments,
    ).filter((f) => f.planId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _planAssignmentsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CropPlansTableFilterComposer
    extends Composer<_$AppDatabase, $CropPlansTable> {
  $$CropPlansTableFilterComposer({
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

  ColumnFilters<String> get requestId => $composableBuilder(
    column: $table.requestId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get solver => $composableBuilder(
    column: $table.solver,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dataMode => $composableBuilder(
    column: $table.dataMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get netValueRs => $composableBuilder(
    column: $table.netValueRs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get netValueP10Rs => $composableBuilder(
    column: $table.netValueP10Rs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get netValueP90Rs => $composableBuilder(
    column: $table.netValueP90Rs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get waterUsedM3 => $composableBuilder(
    column: $table.waterUsedM3,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get budgetUsedRs => $composableBuilder(
    column: $table.budgetUsedRs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get benchmarkJson => $composableBuilder(
    column: $table.benchmarkJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get advisoryJson => $composableBuilder(
    column: $table.advisoryJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get alternativesJson => $composableBuilder(
    column: $table.alternativesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$FieldsTableFilterComposer get fieldId {
    final $$FieldsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fieldId,
      referencedTable: $db.fields,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FieldsTableFilterComposer(
            $db: $db,
            $table: $db.fields,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> planAssignmentsRefs(
    Expression<bool> Function($$PlanAssignmentsTableFilterComposer f) f,
  ) {
    final $$PlanAssignmentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.planAssignments,
      getReferencedColumn: (t) => t.planId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlanAssignmentsTableFilterComposer(
            $db: $db,
            $table: $db.planAssignments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CropPlansTableOrderingComposer
    extends Composer<_$AppDatabase, $CropPlansTable> {
  $$CropPlansTableOrderingComposer({
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

  ColumnOrderings<String> get requestId => $composableBuilder(
    column: $table.requestId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get solver => $composableBuilder(
    column: $table.solver,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dataMode => $composableBuilder(
    column: $table.dataMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get netValueRs => $composableBuilder(
    column: $table.netValueRs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get netValueP10Rs => $composableBuilder(
    column: $table.netValueP10Rs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get netValueP90Rs => $composableBuilder(
    column: $table.netValueP90Rs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get waterUsedM3 => $composableBuilder(
    column: $table.waterUsedM3,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get budgetUsedRs => $composableBuilder(
    column: $table.budgetUsedRs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get benchmarkJson => $composableBuilder(
    column: $table.benchmarkJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get advisoryJson => $composableBuilder(
    column: $table.advisoryJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get alternativesJson => $composableBuilder(
    column: $table.alternativesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$FieldsTableOrderingComposer get fieldId {
    final $$FieldsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fieldId,
      referencedTable: $db.fields,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FieldsTableOrderingComposer(
            $db: $db,
            $table: $db.fields,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CropPlansTableAnnotationComposer
    extends Composer<_$AppDatabase, $CropPlansTable> {
  $$CropPlansTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get requestId =>
      $composableBuilder(column: $table.requestId, builder: (column) => column);

  GeneratedColumn<String> get solver =>
      $composableBuilder(column: $table.solver, builder: (column) => column);

  GeneratedColumn<String> get dataMode =>
      $composableBuilder(column: $table.dataMode, builder: (column) => column);

  GeneratedColumn<double> get netValueRs => $composableBuilder(
    column: $table.netValueRs,
    builder: (column) => column,
  );

  GeneratedColumn<double> get netValueP10Rs => $composableBuilder(
    column: $table.netValueP10Rs,
    builder: (column) => column,
  );

  GeneratedColumn<double> get netValueP90Rs => $composableBuilder(
    column: $table.netValueP90Rs,
    builder: (column) => column,
  );

  GeneratedColumn<double> get waterUsedM3 => $composableBuilder(
    column: $table.waterUsedM3,
    builder: (column) => column,
  );

  GeneratedColumn<double> get budgetUsedRs => $composableBuilder(
    column: $table.budgetUsedRs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get benchmarkJson => $composableBuilder(
    column: $table.benchmarkJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get advisoryJson => $composableBuilder(
    column: $table.advisoryJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get alternativesJson => $composableBuilder(
    column: $table.alternativesJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$FieldsTableAnnotationComposer get fieldId {
    final $$FieldsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fieldId,
      referencedTable: $db.fields,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FieldsTableAnnotationComposer(
            $db: $db,
            $table: $db.fields,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> planAssignmentsRefs<T extends Object>(
    Expression<T> Function($$PlanAssignmentsTableAnnotationComposer a) f,
  ) {
    final $$PlanAssignmentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.planAssignments,
      getReferencedColumn: (t) => t.planId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlanAssignmentsTableAnnotationComposer(
            $db: $db,
            $table: $db.planAssignments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CropPlansTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CropPlansTable,
          CropPlan,
          $$CropPlansTableFilterComposer,
          $$CropPlansTableOrderingComposer,
          $$CropPlansTableAnnotationComposer,
          $$CropPlansTableCreateCompanionBuilder,
          $$CropPlansTableUpdateCompanionBuilder,
          (CropPlan, $$CropPlansTableReferences),
          CropPlan,
          PrefetchHooks Function({bool fieldId, bool planAssignmentsRefs})
        > {
  $$CropPlansTableTableManager(_$AppDatabase db, $CropPlansTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CropPlansTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CropPlansTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CropPlansTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> requestId = const Value.absent(),
                Value<String> fieldId = const Value.absent(),
                Value<String> solver = const Value.absent(),
                Value<String> dataMode = const Value.absent(),
                Value<double> netValueRs = const Value.absent(),
                Value<double> netValueP10Rs = const Value.absent(),
                Value<double> netValueP90Rs = const Value.absent(),
                Value<double> waterUsedM3 = const Value.absent(),
                Value<double> budgetUsedRs = const Value.absent(),
                Value<String> benchmarkJson = const Value.absent(),
                Value<String> advisoryJson = const Value.absent(),
                Value<String> alternativesJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => CropPlansCompanion(
                id: id,
                requestId: requestId,
                fieldId: fieldId,
                solver: solver,
                dataMode: dataMode,
                netValueRs: netValueRs,
                netValueP10Rs: netValueP10Rs,
                netValueP90Rs: netValueP90Rs,
                waterUsedM3: waterUsedM3,
                budgetUsedRs: budgetUsedRs,
                benchmarkJson: benchmarkJson,
                advisoryJson: advisoryJson,
                alternativesJson: alternativesJson,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String requestId,
                required String fieldId,
                required String solver,
                required String dataMode,
                required double netValueRs,
                required double netValueP10Rs,
                required double netValueP90Rs,
                required double waterUsedM3,
                required double budgetUsedRs,
                required String benchmarkJson,
                required String advisoryJson,
                required String alternativesJson,
                Value<DateTime> createdAt = const Value.absent(),
              }) => CropPlansCompanion.insert(
                id: id,
                requestId: requestId,
                fieldId: fieldId,
                solver: solver,
                dataMode: dataMode,
                netValueRs: netValueRs,
                netValueP10Rs: netValueP10Rs,
                netValueP90Rs: netValueP90Rs,
                waterUsedM3: waterUsedM3,
                budgetUsedRs: budgetUsedRs,
                benchmarkJson: benchmarkJson,
                advisoryJson: advisoryJson,
                alternativesJson: alternativesJson,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CropPlansTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({fieldId = false, planAssignmentsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (planAssignmentsRefs) db.planAssignments,
                  ],
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
                        if (fieldId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.fieldId,
                                    referencedTable: $$CropPlansTableReferences
                                        ._fieldIdTable(db),
                                    referencedColumn: $$CropPlansTableReferences
                                        ._fieldIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (planAssignmentsRefs)
                        await $_getPrefetchedData<
                          CropPlan,
                          $CropPlansTable,
                          PlanAssignment
                        >(
                          currentTable: table,
                          referencedTable: $$CropPlansTableReferences
                              ._planAssignmentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CropPlansTableReferences(
                                db,
                                table,
                                p0,
                              ).planAssignmentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.planId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$CropPlansTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CropPlansTable,
      CropPlan,
      $$CropPlansTableFilterComposer,
      $$CropPlansTableOrderingComposer,
      $$CropPlansTableAnnotationComposer,
      $$CropPlansTableCreateCompanionBuilder,
      $$CropPlansTableUpdateCompanionBuilder,
      (CropPlan, $$CropPlansTableReferences),
      CropPlan,
      PrefetchHooks Function({bool fieldId, bool planAssignmentsRefs})
    >;
typedef $$PlanAssignmentsTableCreateCompanionBuilder =
    PlanAssignmentsCompanion Function({
      Value<int> id,
      required int planId,
      required String plotId,
      required String crop,
      required double yieldTHa,
      required double p10,
      required double p90,
    });
typedef $$PlanAssignmentsTableUpdateCompanionBuilder =
    PlanAssignmentsCompanion Function({
      Value<int> id,
      Value<int> planId,
      Value<String> plotId,
      Value<String> crop,
      Value<double> yieldTHa,
      Value<double> p10,
      Value<double> p90,
    });

final class $$PlanAssignmentsTableReferences
    extends
        BaseReferences<_$AppDatabase, $PlanAssignmentsTable, PlanAssignment> {
  $$PlanAssignmentsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CropPlansTable _planIdTable(_$AppDatabase db) =>
      db.cropPlans.createAlias('plan_assignments__plan_id__crop_plans__id');

  $$CropPlansTableProcessedTableManager get planId {
    final $_column = $_itemColumn<int>('plan_id')!;

    final manager = $$CropPlansTableTableManager(
      $_db,
      $_db.cropPlans,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_planIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PlanAssignmentsTableFilterComposer
    extends Composer<_$AppDatabase, $PlanAssignmentsTable> {
  $$PlanAssignmentsTableFilterComposer({
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

  ColumnFilters<String> get plotId => $composableBuilder(
    column: $table.plotId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get crop => $composableBuilder(
    column: $table.crop,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get yieldTHa => $composableBuilder(
    column: $table.yieldTHa,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get p10 => $composableBuilder(
    column: $table.p10,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get p90 => $composableBuilder(
    column: $table.p90,
    builder: (column) => ColumnFilters(column),
  );

  $$CropPlansTableFilterComposer get planId {
    final $$CropPlansTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.planId,
      referencedTable: $db.cropPlans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CropPlansTableFilterComposer(
            $db: $db,
            $table: $db.cropPlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlanAssignmentsTableOrderingComposer
    extends Composer<_$AppDatabase, $PlanAssignmentsTable> {
  $$PlanAssignmentsTableOrderingComposer({
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

  ColumnOrderings<String> get plotId => $composableBuilder(
    column: $table.plotId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get crop => $composableBuilder(
    column: $table.crop,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get yieldTHa => $composableBuilder(
    column: $table.yieldTHa,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get p10 => $composableBuilder(
    column: $table.p10,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get p90 => $composableBuilder(
    column: $table.p90,
    builder: (column) => ColumnOrderings(column),
  );

  $$CropPlansTableOrderingComposer get planId {
    final $$CropPlansTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.planId,
      referencedTable: $db.cropPlans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CropPlansTableOrderingComposer(
            $db: $db,
            $table: $db.cropPlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlanAssignmentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlanAssignmentsTable> {
  $$PlanAssignmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get plotId =>
      $composableBuilder(column: $table.plotId, builder: (column) => column);

  GeneratedColumn<String> get crop =>
      $composableBuilder(column: $table.crop, builder: (column) => column);

  GeneratedColumn<double> get yieldTHa =>
      $composableBuilder(column: $table.yieldTHa, builder: (column) => column);

  GeneratedColumn<double> get p10 =>
      $composableBuilder(column: $table.p10, builder: (column) => column);

  GeneratedColumn<double> get p90 =>
      $composableBuilder(column: $table.p90, builder: (column) => column);

  $$CropPlansTableAnnotationComposer get planId {
    final $$CropPlansTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.planId,
      referencedTable: $db.cropPlans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CropPlansTableAnnotationComposer(
            $db: $db,
            $table: $db.cropPlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlanAssignmentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlanAssignmentsTable,
          PlanAssignment,
          $$PlanAssignmentsTableFilterComposer,
          $$PlanAssignmentsTableOrderingComposer,
          $$PlanAssignmentsTableAnnotationComposer,
          $$PlanAssignmentsTableCreateCompanionBuilder,
          $$PlanAssignmentsTableUpdateCompanionBuilder,
          (PlanAssignment, $$PlanAssignmentsTableReferences),
          PlanAssignment,
          PrefetchHooks Function({bool planId})
        > {
  $$PlanAssignmentsTableTableManager(
    _$AppDatabase db,
    $PlanAssignmentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlanAssignmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlanAssignmentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlanAssignmentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> planId = const Value.absent(),
                Value<String> plotId = const Value.absent(),
                Value<String> crop = const Value.absent(),
                Value<double> yieldTHa = const Value.absent(),
                Value<double> p10 = const Value.absent(),
                Value<double> p90 = const Value.absent(),
              }) => PlanAssignmentsCompanion(
                id: id,
                planId: planId,
                plotId: plotId,
                crop: crop,
                yieldTHa: yieldTHa,
                p10: p10,
                p90: p90,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int planId,
                required String plotId,
                required String crop,
                required double yieldTHa,
                required double p10,
                required double p90,
              }) => PlanAssignmentsCompanion.insert(
                id: id,
                planId: planId,
                plotId: plotId,
                crop: crop,
                yieldTHa: yieldTHa,
                p10: p10,
                p90: p90,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PlanAssignmentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({planId = false}) {
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
                    if (planId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.planId,
                                referencedTable:
                                    $$PlanAssignmentsTableReferences
                                        ._planIdTable(db),
                                referencedColumn:
                                    $$PlanAssignmentsTableReferences
                                        ._planIdTable(db)
                                        .id,
                              )
                              as T;
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

typedef $$PlanAssignmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlanAssignmentsTable,
      PlanAssignment,
      $$PlanAssignmentsTableFilterComposer,
      $$PlanAssignmentsTableOrderingComposer,
      $$PlanAssignmentsTableAnnotationComposer,
      $$PlanAssignmentsTableCreateCompanionBuilder,
      $$PlanAssignmentsTableUpdateCompanionBuilder,
      (PlanAssignment, $$PlanAssignmentsTableReferences),
      PlanAssignment,
      PrefetchHooks Function({bool planId})
    >;
typedef $$SyncQueueItemsTableCreateCompanionBuilder =
    SyncQueueItemsCompanion Function({
      Value<int> id,
      required String kind,
      required String payloadJson,
      required SyncOpStatus status,
      Value<String?> errorMessage,
      Value<DateTime> createdAt,
      Value<DateTime?> lastAttemptAt,
    });
typedef $$SyncQueueItemsTableUpdateCompanionBuilder =
    SyncQueueItemsCompanion Function({
      Value<int> id,
      Value<String> kind,
      Value<String> payloadJson,
      Value<SyncOpStatus> status,
      Value<String?> errorMessage,
      Value<DateTime> createdAt,
      Value<DateTime?> lastAttemptAt,
    });

class $$SyncQueueItemsTableFilterComposer
    extends Composer<_$AppDatabase, $SyncQueueItemsTable> {
  $$SyncQueueItemsTableFilterComposer({
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

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<SyncOpStatus, SyncOpStatus, int> get status =>
      $composableBuilder(
        column: $table.status,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncQueueItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncQueueItemsTable> {
  $$SyncQueueItemsTableOrderingComposer({
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

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncQueueItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncQueueItemsTable> {
  $$SyncQueueItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<SyncOpStatus, int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => column,
  );
}

class $$SyncQueueItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncQueueItemsTable,
          SyncQueueItem,
          $$SyncQueueItemsTableFilterComposer,
          $$SyncQueueItemsTableOrderingComposer,
          $$SyncQueueItemsTableAnnotationComposer,
          $$SyncQueueItemsTableCreateCompanionBuilder,
          $$SyncQueueItemsTableUpdateCompanionBuilder,
          (
            SyncQueueItem,
            BaseReferences<_$AppDatabase, $SyncQueueItemsTable, SyncQueueItem>,
          ),
          SyncQueueItem,
          PrefetchHooks Function()
        > {
  $$SyncQueueItemsTableTableManager(
    _$AppDatabase db,
    $SyncQueueItemsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncQueueItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncQueueItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncQueueItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<SyncOpStatus> status = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> lastAttemptAt = const Value.absent(),
              }) => SyncQueueItemsCompanion(
                id: id,
                kind: kind,
                payloadJson: payloadJson,
                status: status,
                errorMessage: errorMessage,
                createdAt: createdAt,
                lastAttemptAt: lastAttemptAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String kind,
                required String payloadJson,
                required SyncOpStatus status,
                Value<String?> errorMessage = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> lastAttemptAt = const Value.absent(),
              }) => SyncQueueItemsCompanion.insert(
                id: id,
                kind: kind,
                payloadJson: payloadJson,
                status: status,
                errorMessage: errorMessage,
                createdAt: createdAt,
                lastAttemptAt: lastAttemptAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncQueueItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncQueueItemsTable,
      SyncQueueItem,
      $$SyncQueueItemsTableFilterComposer,
      $$SyncQueueItemsTableOrderingComposer,
      $$SyncQueueItemsTableAnnotationComposer,
      $$SyncQueueItemsTableCreateCompanionBuilder,
      $$SyncQueueItemsTableUpdateCompanionBuilder,
      (
        SyncQueueItem,
        BaseReferences<_$AppDatabase, $SyncQueueItemsTable, SyncQueueItem>,
      ),
      SyncQueueItem,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$FieldsTableTableManager get fields =>
      $$FieldsTableTableManager(_db, _db.fields);
  $$PlotsTableTableManager get plots =>
      $$PlotsTableTableManager(_db, _db.plots);
  $$CropPlansTableTableManager get cropPlans =>
      $$CropPlansTableTableManager(_db, _db.cropPlans);
  $$PlanAssignmentsTableTableManager get planAssignments =>
      $$PlanAssignmentsTableTableManager(_db, _db.planAssignments);
  $$SyncQueueItemsTableTableManager get syncQueueItems =>
      $$SyncQueueItemsTableTableManager(_db, _db.syncQueueItems);
}
