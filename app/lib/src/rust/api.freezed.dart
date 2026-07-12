// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'api.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TaskDueDto {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TaskDueDto);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TaskDueDto()';
}


}

/// @nodoc
class $TaskDueDtoCopyWith<$Res>  {
$TaskDueDtoCopyWith(TaskDueDto _, $Res Function(TaskDueDto) __);
}


/// Adds pattern-matching-related methods to [TaskDueDto].
extension TaskDueDtoPatterns on TaskDueDto {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( TaskDueDto_Date value)?  date,TResult Function( TaskDueDto_DateTime value)?  dateTime,required TResult orElse(),}){
final _that = this;
switch (_that) {
case TaskDueDto_Date() when date != null:
return date(_that);case TaskDueDto_DateTime() when dateTime != null:
return dateTime(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( TaskDueDto_Date value)  date,required TResult Function( TaskDueDto_DateTime value)  dateTime,}){
final _that = this;
switch (_that) {
case TaskDueDto_Date():
return date(_that);case TaskDueDto_DateTime():
return dateTime(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( TaskDueDto_Date value)?  date,TResult? Function( TaskDueDto_DateTime value)?  dateTime,}){
final _that = this;
switch (_that) {
case TaskDueDto_Date() when date != null:
return date(_that);case TaskDueDto_DateTime() when dateTime != null:
return dateTime(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String dueOn)?  date,TResult Function( DateTime dueAt,  String timeZone)?  dateTime,required TResult orElse(),}) {final _that = this;
switch (_that) {
case TaskDueDto_Date() when date != null:
return date(_that.dueOn);case TaskDueDto_DateTime() when dateTime != null:
return dateTime(_that.dueAt,_that.timeZone);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String dueOn)  date,required TResult Function( DateTime dueAt,  String timeZone)  dateTime,}) {final _that = this;
switch (_that) {
case TaskDueDto_Date():
return date(_that.dueOn);case TaskDueDto_DateTime():
return dateTime(_that.dueAt,_that.timeZone);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String dueOn)?  date,TResult? Function( DateTime dueAt,  String timeZone)?  dateTime,}) {final _that = this;
switch (_that) {
case TaskDueDto_Date() when date != null:
return date(_that.dueOn);case TaskDueDto_DateTime() when dateTime != null:
return dateTime(_that.dueAt,_that.timeZone);case _:
  return null;

}
}

}

/// @nodoc


class TaskDueDto_Date extends TaskDueDto {
  const TaskDueDto_Date({required this.dueOn}): super._();
  

 final  String dueOn;

/// Create a copy of TaskDueDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TaskDueDto_DateCopyWith<TaskDueDto_Date> get copyWith => _$TaskDueDto_DateCopyWithImpl<TaskDueDto_Date>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TaskDueDto_Date&&(identical(other.dueOn, dueOn) || other.dueOn == dueOn));
}


@override
int get hashCode => Object.hash(runtimeType,dueOn);

@override
String toString() {
  return 'TaskDueDto.date(dueOn: $dueOn)';
}


}

/// @nodoc
abstract mixin class $TaskDueDto_DateCopyWith<$Res> implements $TaskDueDtoCopyWith<$Res> {
  factory $TaskDueDto_DateCopyWith(TaskDueDto_Date value, $Res Function(TaskDueDto_Date) _then) = _$TaskDueDto_DateCopyWithImpl;
@useResult
$Res call({
 String dueOn
});




}
/// @nodoc
class _$TaskDueDto_DateCopyWithImpl<$Res>
    implements $TaskDueDto_DateCopyWith<$Res> {
  _$TaskDueDto_DateCopyWithImpl(this._self, this._then);

  final TaskDueDto_Date _self;
  final $Res Function(TaskDueDto_Date) _then;

/// Create a copy of TaskDueDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? dueOn = null,}) {
  return _then(TaskDueDto_Date(
dueOn: null == dueOn ? _self.dueOn : dueOn // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class TaskDueDto_DateTime extends TaskDueDto {
  const TaskDueDto_DateTime({required this.dueAt, required this.timeZone}): super._();
  

 final  DateTime dueAt;
 final  String timeZone;

/// Create a copy of TaskDueDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TaskDueDto_DateTimeCopyWith<TaskDueDto_DateTime> get copyWith => _$TaskDueDto_DateTimeCopyWithImpl<TaskDueDto_DateTime>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TaskDueDto_DateTime&&(identical(other.dueAt, dueAt) || other.dueAt == dueAt)&&(identical(other.timeZone, timeZone) || other.timeZone == timeZone));
}


@override
int get hashCode => Object.hash(runtimeType,dueAt,timeZone);

@override
String toString() {
  return 'TaskDueDto.dateTime(dueAt: $dueAt, timeZone: $timeZone)';
}


}

/// @nodoc
abstract mixin class $TaskDueDto_DateTimeCopyWith<$Res> implements $TaskDueDtoCopyWith<$Res> {
  factory $TaskDueDto_DateTimeCopyWith(TaskDueDto_DateTime value, $Res Function(TaskDueDto_DateTime) _then) = _$TaskDueDto_DateTimeCopyWithImpl;
@useResult
$Res call({
 DateTime dueAt, String timeZone
});




}
/// @nodoc
class _$TaskDueDto_DateTimeCopyWithImpl<$Res>
    implements $TaskDueDto_DateTimeCopyWith<$Res> {
  _$TaskDueDto_DateTimeCopyWithImpl(this._self, this._then);

  final TaskDueDto_DateTime _self;
  final $Res Function(TaskDueDto_DateTime) _then;

/// Create a copy of TaskDueDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? dueAt = null,Object? timeZone = null,}) {
  return _then(TaskDueDto_DateTime(
dueAt: null == dueAt ? _self.dueAt : dueAt // ignore: cast_nullable_to_non_nullable
as DateTime,timeZone: null == timeZone ? _self.timeZone : timeZone // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$TaskDueInput {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TaskDueInput);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TaskDueInput()';
}


}

/// @nodoc
class $TaskDueInputCopyWith<$Res>  {
$TaskDueInputCopyWith(TaskDueInput _, $Res Function(TaskDueInput) __);
}


/// Adds pattern-matching-related methods to [TaskDueInput].
extension TaskDueInputPatterns on TaskDueInput {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( TaskDueInput_Date value)?  date,TResult Function( TaskDueInput_DateTime value)?  dateTime,required TResult orElse(),}){
final _that = this;
switch (_that) {
case TaskDueInput_Date() when date != null:
return date(_that);case TaskDueInput_DateTime() when dateTime != null:
return dateTime(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( TaskDueInput_Date value)  date,required TResult Function( TaskDueInput_DateTime value)  dateTime,}){
final _that = this;
switch (_that) {
case TaskDueInput_Date():
return date(_that);case TaskDueInput_DateTime():
return dateTime(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( TaskDueInput_Date value)?  date,TResult? Function( TaskDueInput_DateTime value)?  dateTime,}){
final _that = this;
switch (_that) {
case TaskDueInput_Date() when date != null:
return date(_that);case TaskDueInput_DateTime() when dateTime != null:
return dateTime(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String dueOn)?  date,TResult Function( DateTime dueAt,  String timeZone)?  dateTime,required TResult orElse(),}) {final _that = this;
switch (_that) {
case TaskDueInput_Date() when date != null:
return date(_that.dueOn);case TaskDueInput_DateTime() when dateTime != null:
return dateTime(_that.dueAt,_that.timeZone);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String dueOn)  date,required TResult Function( DateTime dueAt,  String timeZone)  dateTime,}) {final _that = this;
switch (_that) {
case TaskDueInput_Date():
return date(_that.dueOn);case TaskDueInput_DateTime():
return dateTime(_that.dueAt,_that.timeZone);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String dueOn)?  date,TResult? Function( DateTime dueAt,  String timeZone)?  dateTime,}) {final _that = this;
switch (_that) {
case TaskDueInput_Date() when date != null:
return date(_that.dueOn);case TaskDueInput_DateTime() when dateTime != null:
return dateTime(_that.dueAt,_that.timeZone);case _:
  return null;

}
}

}

/// @nodoc


class TaskDueInput_Date extends TaskDueInput {
  const TaskDueInput_Date({required this.dueOn}): super._();
  

 final  String dueOn;

/// Create a copy of TaskDueInput
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TaskDueInput_DateCopyWith<TaskDueInput_Date> get copyWith => _$TaskDueInput_DateCopyWithImpl<TaskDueInput_Date>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TaskDueInput_Date&&(identical(other.dueOn, dueOn) || other.dueOn == dueOn));
}


@override
int get hashCode => Object.hash(runtimeType,dueOn);

@override
String toString() {
  return 'TaskDueInput.date(dueOn: $dueOn)';
}


}

/// @nodoc
abstract mixin class $TaskDueInput_DateCopyWith<$Res> implements $TaskDueInputCopyWith<$Res> {
  factory $TaskDueInput_DateCopyWith(TaskDueInput_Date value, $Res Function(TaskDueInput_Date) _then) = _$TaskDueInput_DateCopyWithImpl;
@useResult
$Res call({
 String dueOn
});




}
/// @nodoc
class _$TaskDueInput_DateCopyWithImpl<$Res>
    implements $TaskDueInput_DateCopyWith<$Res> {
  _$TaskDueInput_DateCopyWithImpl(this._self, this._then);

  final TaskDueInput_Date _self;
  final $Res Function(TaskDueInput_Date) _then;

/// Create a copy of TaskDueInput
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? dueOn = null,}) {
  return _then(TaskDueInput_Date(
dueOn: null == dueOn ? _self.dueOn : dueOn // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class TaskDueInput_DateTime extends TaskDueInput {
  const TaskDueInput_DateTime({required this.dueAt, required this.timeZone}): super._();
  

 final  DateTime dueAt;
 final  String timeZone;

/// Create a copy of TaskDueInput
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TaskDueInput_DateTimeCopyWith<TaskDueInput_DateTime> get copyWith => _$TaskDueInput_DateTimeCopyWithImpl<TaskDueInput_DateTime>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TaskDueInput_DateTime&&(identical(other.dueAt, dueAt) || other.dueAt == dueAt)&&(identical(other.timeZone, timeZone) || other.timeZone == timeZone));
}


@override
int get hashCode => Object.hash(runtimeType,dueAt,timeZone);

@override
String toString() {
  return 'TaskDueInput.dateTime(dueAt: $dueAt, timeZone: $timeZone)';
}


}

/// @nodoc
abstract mixin class $TaskDueInput_DateTimeCopyWith<$Res> implements $TaskDueInputCopyWith<$Res> {
  factory $TaskDueInput_DateTimeCopyWith(TaskDueInput_DateTime value, $Res Function(TaskDueInput_DateTime) _then) = _$TaskDueInput_DateTimeCopyWithImpl;
@useResult
$Res call({
 DateTime dueAt, String timeZone
});




}
/// @nodoc
class _$TaskDueInput_DateTimeCopyWithImpl<$Res>
    implements $TaskDueInput_DateTimeCopyWith<$Res> {
  _$TaskDueInput_DateTimeCopyWithImpl(this._self, this._then);

  final TaskDueInput_DateTime _self;
  final $Res Function(TaskDueInput_DateTime) _then;

/// Create a copy of TaskDueInput
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? dueAt = null,Object? timeZone = null,}) {
  return _then(TaskDueInput_DateTime(
dueAt: null == dueAt ? _self.dueAt : dueAt // ignore: cast_nullable_to_non_nullable
as DateTime,timeZone: null == timeZone ? _self.timeZone : timeZone // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
