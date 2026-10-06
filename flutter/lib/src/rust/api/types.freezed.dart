// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'types.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ApiError {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ApiError()';
}


}

/// @nodoc
class $ApiErrorCopyWith<$Res>  {
$ApiErrorCopyWith(ApiError _, $Res Function(ApiError) __);
}


/// Adds pattern-matching-related methods to [ApiError].
extension ApiErrorPatterns on ApiError {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ApiError_InvalidHomeserver value)?  invalidHomeserver,TResult Function( ApiError_ClientInitialization value)?  clientInitialization,TResult Function( ApiError_AlreadyAuthenticated value)?  alreadyAuthenticated,TResult Function( ApiError_InvalidCredentials value)?  invalidCredentials,TResult Function( ApiError_HomeserverUnreachable value)?  homeserverUnreachable,TResult Function( ApiError_AuthenticationFailed value)?  authenticationFailed,TResult Function( ApiError_InvalidSession value)?  invalidSession,TResult Function( ApiError_NotAuthenticated value)?  notAuthenticated,TResult Function( ApiError_SessionRevoked value)?  sessionRevoked,TResult Function( ApiError_SyncFailed value)?  syncFailed,TResult Function( ApiError_AlreadySyncing value)?  alreadySyncing,TResult Function( ApiError_RoomNotFound value)?  roomNotFound,TResult Function( ApiError_NotJoined value)?  notJoined,TResult Function( ApiError_InvalidMessage value)?  invalidMessage,TResult Function( ApiError_MessageLoadFailed value)?  messageLoadFailed,TResult Function( ApiError_MessageSendFailed value)?  messageSendFailed,TResult Function( ApiError_Storage value)?  storage,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ApiError_InvalidHomeserver() when invalidHomeserver != null:
return invalidHomeserver(_that);case ApiError_ClientInitialization() when clientInitialization != null:
return clientInitialization(_that);case ApiError_AlreadyAuthenticated() when alreadyAuthenticated != null:
return alreadyAuthenticated(_that);case ApiError_InvalidCredentials() when invalidCredentials != null:
return invalidCredentials(_that);case ApiError_HomeserverUnreachable() when homeserverUnreachable != null:
return homeserverUnreachable(_that);case ApiError_AuthenticationFailed() when authenticationFailed != null:
return authenticationFailed(_that);case ApiError_InvalidSession() when invalidSession != null:
return invalidSession(_that);case ApiError_NotAuthenticated() when notAuthenticated != null:
return notAuthenticated(_that);case ApiError_SessionRevoked() when sessionRevoked != null:
return sessionRevoked(_that);case ApiError_SyncFailed() when syncFailed != null:
return syncFailed(_that);case ApiError_AlreadySyncing() when alreadySyncing != null:
return alreadySyncing(_that);case ApiError_RoomNotFound() when roomNotFound != null:
return roomNotFound(_that);case ApiError_NotJoined() when notJoined != null:
return notJoined(_that);case ApiError_InvalidMessage() when invalidMessage != null:
return invalidMessage(_that);case ApiError_MessageLoadFailed() when messageLoadFailed != null:
return messageLoadFailed(_that);case ApiError_MessageSendFailed() when messageSendFailed != null:
return messageSendFailed(_that);case ApiError_Storage() when storage != null:
return storage(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ApiError_InvalidHomeserver value)  invalidHomeserver,required TResult Function( ApiError_ClientInitialization value)  clientInitialization,required TResult Function( ApiError_AlreadyAuthenticated value)  alreadyAuthenticated,required TResult Function( ApiError_InvalidCredentials value)  invalidCredentials,required TResult Function( ApiError_HomeserverUnreachable value)  homeserverUnreachable,required TResult Function( ApiError_AuthenticationFailed value)  authenticationFailed,required TResult Function( ApiError_InvalidSession value)  invalidSession,required TResult Function( ApiError_NotAuthenticated value)  notAuthenticated,required TResult Function( ApiError_SessionRevoked value)  sessionRevoked,required TResult Function( ApiError_SyncFailed value)  syncFailed,required TResult Function( ApiError_AlreadySyncing value)  alreadySyncing,required TResult Function( ApiError_RoomNotFound value)  roomNotFound,required TResult Function( ApiError_NotJoined value)  notJoined,required TResult Function( ApiError_InvalidMessage value)  invalidMessage,required TResult Function( ApiError_MessageLoadFailed value)  messageLoadFailed,required TResult Function( ApiError_MessageSendFailed value)  messageSendFailed,required TResult Function( ApiError_Storage value)  storage,}){
final _that = this;
switch (_that) {
case ApiError_InvalidHomeserver():
return invalidHomeserver(_that);case ApiError_ClientInitialization():
return clientInitialization(_that);case ApiError_AlreadyAuthenticated():
return alreadyAuthenticated(_that);case ApiError_InvalidCredentials():
return invalidCredentials(_that);case ApiError_HomeserverUnreachable():
return homeserverUnreachable(_that);case ApiError_AuthenticationFailed():
return authenticationFailed(_that);case ApiError_InvalidSession():
return invalidSession(_that);case ApiError_NotAuthenticated():
return notAuthenticated(_that);case ApiError_SessionRevoked():
return sessionRevoked(_that);case ApiError_SyncFailed():
return syncFailed(_that);case ApiError_AlreadySyncing():
return alreadySyncing(_that);case ApiError_RoomNotFound():
return roomNotFound(_that);case ApiError_NotJoined():
return notJoined(_that);case ApiError_InvalidMessage():
return invalidMessage(_that);case ApiError_MessageLoadFailed():
return messageLoadFailed(_that);case ApiError_MessageSendFailed():
return messageSendFailed(_that);case ApiError_Storage():
return storage(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ApiError_InvalidHomeserver value)?  invalidHomeserver,TResult? Function( ApiError_ClientInitialization value)?  clientInitialization,TResult? Function( ApiError_AlreadyAuthenticated value)?  alreadyAuthenticated,TResult? Function( ApiError_InvalidCredentials value)?  invalidCredentials,TResult? Function( ApiError_HomeserverUnreachable value)?  homeserverUnreachable,TResult? Function( ApiError_AuthenticationFailed value)?  authenticationFailed,TResult? Function( ApiError_InvalidSession value)?  invalidSession,TResult? Function( ApiError_NotAuthenticated value)?  notAuthenticated,TResult? Function( ApiError_SessionRevoked value)?  sessionRevoked,TResult? Function( ApiError_SyncFailed value)?  syncFailed,TResult? Function( ApiError_AlreadySyncing value)?  alreadySyncing,TResult? Function( ApiError_RoomNotFound value)?  roomNotFound,TResult? Function( ApiError_NotJoined value)?  notJoined,TResult? Function( ApiError_InvalidMessage value)?  invalidMessage,TResult? Function( ApiError_MessageLoadFailed value)?  messageLoadFailed,TResult? Function( ApiError_MessageSendFailed value)?  messageSendFailed,TResult? Function( ApiError_Storage value)?  storage,}){
final _that = this;
switch (_that) {
case ApiError_InvalidHomeserver() when invalidHomeserver != null:
return invalidHomeserver(_that);case ApiError_ClientInitialization() when clientInitialization != null:
return clientInitialization(_that);case ApiError_AlreadyAuthenticated() when alreadyAuthenticated != null:
return alreadyAuthenticated(_that);case ApiError_InvalidCredentials() when invalidCredentials != null:
return invalidCredentials(_that);case ApiError_HomeserverUnreachable() when homeserverUnreachable != null:
return homeserverUnreachable(_that);case ApiError_AuthenticationFailed() when authenticationFailed != null:
return authenticationFailed(_that);case ApiError_InvalidSession() when invalidSession != null:
return invalidSession(_that);case ApiError_NotAuthenticated() when notAuthenticated != null:
return notAuthenticated(_that);case ApiError_SessionRevoked() when sessionRevoked != null:
return sessionRevoked(_that);case ApiError_SyncFailed() when syncFailed != null:
return syncFailed(_that);case ApiError_AlreadySyncing() when alreadySyncing != null:
return alreadySyncing(_that);case ApiError_RoomNotFound() when roomNotFound != null:
return roomNotFound(_that);case ApiError_NotJoined() when notJoined != null:
return notJoined(_that);case ApiError_InvalidMessage() when invalidMessage != null:
return invalidMessage(_that);case ApiError_MessageLoadFailed() when messageLoadFailed != null:
return messageLoadFailed(_that);case ApiError_MessageSendFailed() when messageSendFailed != null:
return messageSendFailed(_that);case ApiError_Storage() when storage != null:
return storage(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String reason)?  invalidHomeserver,TResult Function()?  clientInitialization,TResult Function()?  alreadyAuthenticated,TResult Function()?  invalidCredentials,TResult Function()?  homeserverUnreachable,TResult Function()?  authenticationFailed,TResult Function()?  invalidSession,TResult Function()?  notAuthenticated,TResult Function()?  sessionRevoked,TResult Function()?  syncFailed,TResult Function()?  alreadySyncing,TResult Function()?  roomNotFound,TResult Function()?  notJoined,TResult Function()?  invalidMessage,TResult Function()?  messageLoadFailed,TResult Function()?  messageSendFailed,TResult Function()?  storage,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ApiError_InvalidHomeserver() when invalidHomeserver != null:
return invalidHomeserver(_that.reason);case ApiError_ClientInitialization() when clientInitialization != null:
return clientInitialization();case ApiError_AlreadyAuthenticated() when alreadyAuthenticated != null:
return alreadyAuthenticated();case ApiError_InvalidCredentials() when invalidCredentials != null:
return invalidCredentials();case ApiError_HomeserverUnreachable() when homeserverUnreachable != null:
return homeserverUnreachable();case ApiError_AuthenticationFailed() when authenticationFailed != null:
return authenticationFailed();case ApiError_InvalidSession() when invalidSession != null:
return invalidSession();case ApiError_NotAuthenticated() when notAuthenticated != null:
return notAuthenticated();case ApiError_SessionRevoked() when sessionRevoked != null:
return sessionRevoked();case ApiError_SyncFailed() when syncFailed != null:
return syncFailed();case ApiError_AlreadySyncing() when alreadySyncing != null:
return alreadySyncing();case ApiError_RoomNotFound() when roomNotFound != null:
return roomNotFound();case ApiError_NotJoined() when notJoined != null:
return notJoined();case ApiError_InvalidMessage() when invalidMessage != null:
return invalidMessage();case ApiError_MessageLoadFailed() when messageLoadFailed != null:
return messageLoadFailed();case ApiError_MessageSendFailed() when messageSendFailed != null:
return messageSendFailed();case ApiError_Storage() when storage != null:
return storage();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String reason)  invalidHomeserver,required TResult Function()  clientInitialization,required TResult Function()  alreadyAuthenticated,required TResult Function()  invalidCredentials,required TResult Function()  homeserverUnreachable,required TResult Function()  authenticationFailed,required TResult Function()  invalidSession,required TResult Function()  notAuthenticated,required TResult Function()  sessionRevoked,required TResult Function()  syncFailed,required TResult Function()  alreadySyncing,required TResult Function()  roomNotFound,required TResult Function()  notJoined,required TResult Function()  invalidMessage,required TResult Function()  messageLoadFailed,required TResult Function()  messageSendFailed,required TResult Function()  storage,}) {final _that = this;
switch (_that) {
case ApiError_InvalidHomeserver():
return invalidHomeserver(_that.reason);case ApiError_ClientInitialization():
return clientInitialization();case ApiError_AlreadyAuthenticated():
return alreadyAuthenticated();case ApiError_InvalidCredentials():
return invalidCredentials();case ApiError_HomeserverUnreachable():
return homeserverUnreachable();case ApiError_AuthenticationFailed():
return authenticationFailed();case ApiError_InvalidSession():
return invalidSession();case ApiError_NotAuthenticated():
return notAuthenticated();case ApiError_SessionRevoked():
return sessionRevoked();case ApiError_SyncFailed():
return syncFailed();case ApiError_AlreadySyncing():
return alreadySyncing();case ApiError_RoomNotFound():
return roomNotFound();case ApiError_NotJoined():
return notJoined();case ApiError_InvalidMessage():
return invalidMessage();case ApiError_MessageLoadFailed():
return messageLoadFailed();case ApiError_MessageSendFailed():
return messageSendFailed();case ApiError_Storage():
return storage();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String reason)?  invalidHomeserver,TResult? Function()?  clientInitialization,TResult? Function()?  alreadyAuthenticated,TResult? Function()?  invalidCredentials,TResult? Function()?  homeserverUnreachable,TResult? Function()?  authenticationFailed,TResult? Function()?  invalidSession,TResult? Function()?  notAuthenticated,TResult? Function()?  sessionRevoked,TResult? Function()?  syncFailed,TResult? Function()?  alreadySyncing,TResult? Function()?  roomNotFound,TResult? Function()?  notJoined,TResult? Function()?  invalidMessage,TResult? Function()?  messageLoadFailed,TResult? Function()?  messageSendFailed,TResult? Function()?  storage,}) {final _that = this;
switch (_that) {
case ApiError_InvalidHomeserver() when invalidHomeserver != null:
return invalidHomeserver(_that.reason);case ApiError_ClientInitialization() when clientInitialization != null:
return clientInitialization();case ApiError_AlreadyAuthenticated() when alreadyAuthenticated != null:
return alreadyAuthenticated();case ApiError_InvalidCredentials() when invalidCredentials != null:
return invalidCredentials();case ApiError_HomeserverUnreachable() when homeserverUnreachable != null:
return homeserverUnreachable();case ApiError_AuthenticationFailed() when authenticationFailed != null:
return authenticationFailed();case ApiError_InvalidSession() when invalidSession != null:
return invalidSession();case ApiError_NotAuthenticated() when notAuthenticated != null:
return notAuthenticated();case ApiError_SessionRevoked() when sessionRevoked != null:
return sessionRevoked();case ApiError_SyncFailed() when syncFailed != null:
return syncFailed();case ApiError_AlreadySyncing() when alreadySyncing != null:
return alreadySyncing();case ApiError_RoomNotFound() when roomNotFound != null:
return roomNotFound();case ApiError_NotJoined() when notJoined != null:
return notJoined();case ApiError_InvalidMessage() when invalidMessage != null:
return invalidMessage();case ApiError_MessageLoadFailed() when messageLoadFailed != null:
return messageLoadFailed();case ApiError_MessageSendFailed() when messageSendFailed != null:
return messageSendFailed();case ApiError_Storage() when storage != null:
return storage();case _:
  return null;

}
}

}

/// @nodoc


class ApiError_InvalidHomeserver extends ApiError {
  const ApiError_InvalidHomeserver({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of ApiError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ApiError_InvalidHomeserverCopyWith<ApiError_InvalidHomeserver> get copyWith => _$ApiError_InvalidHomeserverCopyWithImpl<ApiError_InvalidHomeserver>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiError_InvalidHomeserver&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reason);
}

@override
String toString() {
    return 'ApiError.invalidHomeserver(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $ApiError_InvalidHomeserverCopyWith<$Res> implements $ApiErrorCopyWith<$Res> {
  factory $ApiError_InvalidHomeserverCopyWith(ApiError_InvalidHomeserver value, $Res Function(ApiError_InvalidHomeserver) _then) = _$ApiError_InvalidHomeserverCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$ApiError_InvalidHomeserverCopyWithImpl<$Res>
    implements $ApiError_InvalidHomeserverCopyWith<$Res> {
  _$ApiError_InvalidHomeserverCopyWithImpl(this._self, this._then);

  final ApiError_InvalidHomeserver _self;
  final $Res Function(ApiError_InvalidHomeserver) _then;

/// Create a copy of ApiError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(ApiError_InvalidHomeserver(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ApiError_ClientInitialization extends ApiError {
  const ApiError_ClientInitialization(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiError_ClientInitialization);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ApiError.clientInitialization()';
}


}




/// @nodoc


class ApiError_AlreadyAuthenticated extends ApiError {
  const ApiError_AlreadyAuthenticated(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiError_AlreadyAuthenticated);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ApiError.alreadyAuthenticated()';
}


}




/// @nodoc


class ApiError_InvalidCredentials extends ApiError {
  const ApiError_InvalidCredentials(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiError_InvalidCredentials);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ApiError.invalidCredentials()';
}


}




/// @nodoc


class ApiError_HomeserverUnreachable extends ApiError {
  const ApiError_HomeserverUnreachable(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiError_HomeserverUnreachable);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ApiError.homeserverUnreachable()';
}


}




/// @nodoc


class ApiError_AuthenticationFailed extends ApiError {
  const ApiError_AuthenticationFailed(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiError_AuthenticationFailed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ApiError.authenticationFailed()';
}


}




/// @nodoc


class ApiError_InvalidSession extends ApiError {
  const ApiError_InvalidSession(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiError_InvalidSession);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ApiError.invalidSession()';
}


}




/// @nodoc


class ApiError_NotAuthenticated extends ApiError {
  const ApiError_NotAuthenticated(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiError_NotAuthenticated);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ApiError.notAuthenticated()';
}


}




/// @nodoc


class ApiError_SessionRevoked extends ApiError {
  const ApiError_SessionRevoked(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiError_SessionRevoked);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ApiError.sessionRevoked()';
}


}




/// @nodoc


class ApiError_SyncFailed extends ApiError {
  const ApiError_SyncFailed(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiError_SyncFailed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ApiError.syncFailed()';
}


}




/// @nodoc


class ApiError_AlreadySyncing extends ApiError {
  const ApiError_AlreadySyncing(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiError_AlreadySyncing);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ApiError.alreadySyncing()';
}


}




/// @nodoc


class ApiError_RoomNotFound extends ApiError {
  const ApiError_RoomNotFound(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiError_RoomNotFound);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ApiError.roomNotFound()';
}


}




/// @nodoc


class ApiError_NotJoined extends ApiError {
  const ApiError_NotJoined(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiError_NotJoined);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ApiError.notJoined()';
}


}




/// @nodoc


class ApiError_InvalidMessage extends ApiError {
  const ApiError_InvalidMessage(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiError_InvalidMessage);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ApiError.invalidMessage()';
}


}




/// @nodoc


class ApiError_MessageLoadFailed extends ApiError {
  const ApiError_MessageLoadFailed(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiError_MessageLoadFailed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ApiError.messageLoadFailed()';
}


}




/// @nodoc


class ApiError_MessageSendFailed extends ApiError {
  const ApiError_MessageSendFailed(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiError_MessageSendFailed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ApiError.messageSendFailed()';
}


}




/// @nodoc


class ApiError_Storage extends ApiError {
  const ApiError_Storage(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiError_Storage);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ApiError.storage()';
}


}




/// @nodoc
mixin _$CoreEvent {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'CoreEvent()';
}


}

/// @nodoc
class $CoreEventCopyWith<$Res>  {
$CoreEventCopyWith(CoreEvent _, $Res Function(CoreEvent) __);
}


/// Adds pattern-matching-related methods to [CoreEvent].
extension CoreEventPatterns on CoreEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( CoreEvent_MessageReceived value)?  messageReceived,TResult Function( CoreEvent_RoomsChanged value)?  roomsChanged,TResult Function( CoreEvent_TimelineGap value)?  timelineGap,TResult Function( CoreEvent_SyncStateChanged value)?  syncStateChanged,TResult Function( CoreEvent_SessionRevoked value)?  sessionRevoked,TResult Function( CoreEvent_EventsLost value)?  eventsLost,required TResult orElse(),}){
final _that = this;
switch (_that) {
case CoreEvent_MessageReceived() when messageReceived != null:
return messageReceived(_that);case CoreEvent_RoomsChanged() when roomsChanged != null:
return roomsChanged(_that);case CoreEvent_TimelineGap() when timelineGap != null:
return timelineGap(_that);case CoreEvent_SyncStateChanged() when syncStateChanged != null:
return syncStateChanged(_that);case CoreEvent_SessionRevoked() when sessionRevoked != null:
return sessionRevoked(_that);case CoreEvent_EventsLost() when eventsLost != null:
return eventsLost(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( CoreEvent_MessageReceived value)  messageReceived,required TResult Function( CoreEvent_RoomsChanged value)  roomsChanged,required TResult Function( CoreEvent_TimelineGap value)  timelineGap,required TResult Function( CoreEvent_SyncStateChanged value)  syncStateChanged,required TResult Function( CoreEvent_SessionRevoked value)  sessionRevoked,required TResult Function( CoreEvent_EventsLost value)  eventsLost,}){
final _that = this;
switch (_that) {
case CoreEvent_MessageReceived():
return messageReceived(_that);case CoreEvent_RoomsChanged():
return roomsChanged(_that);case CoreEvent_TimelineGap():
return timelineGap(_that);case CoreEvent_SyncStateChanged():
return syncStateChanged(_that);case CoreEvent_SessionRevoked():
return sessionRevoked(_that);case CoreEvent_EventsLost():
return eventsLost(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( CoreEvent_MessageReceived value)?  messageReceived,TResult? Function( CoreEvent_RoomsChanged value)?  roomsChanged,TResult? Function( CoreEvent_TimelineGap value)?  timelineGap,TResult? Function( CoreEvent_SyncStateChanged value)?  syncStateChanged,TResult? Function( CoreEvent_SessionRevoked value)?  sessionRevoked,TResult? Function( CoreEvent_EventsLost value)?  eventsLost,}){
final _that = this;
switch (_that) {
case CoreEvent_MessageReceived() when messageReceived != null:
return messageReceived(_that);case CoreEvent_RoomsChanged() when roomsChanged != null:
return roomsChanged(_that);case CoreEvent_TimelineGap() when timelineGap != null:
return timelineGap(_that);case CoreEvent_SyncStateChanged() when syncStateChanged != null:
return syncStateChanged(_that);case CoreEvent_SessionRevoked() when sessionRevoked != null:
return sessionRevoked(_that);case CoreEvent_EventsLost() when eventsLost != null:
return eventsLost(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String roomId,  Message message)?  messageReceived,TResult Function()?  roomsChanged,TResult Function( String roomId)?  timelineGap,TResult Function( SyncState state)?  syncStateChanged,TResult Function()?  sessionRevoked,TResult Function( PlatformInt64 count)?  eventsLost,required TResult orElse(),}) {final _that = this;
switch (_that) {
case CoreEvent_MessageReceived() when messageReceived != null:
return messageReceived(_that.roomId,_that.message);case CoreEvent_RoomsChanged() when roomsChanged != null:
return roomsChanged();case CoreEvent_TimelineGap() when timelineGap != null:
return timelineGap(_that.roomId);case CoreEvent_SyncStateChanged() when syncStateChanged != null:
return syncStateChanged(_that.state);case CoreEvent_SessionRevoked() when sessionRevoked != null:
return sessionRevoked();case CoreEvent_EventsLost() when eventsLost != null:
return eventsLost(_that.count);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String roomId,  Message message)  messageReceived,required TResult Function()  roomsChanged,required TResult Function( String roomId)  timelineGap,required TResult Function( SyncState state)  syncStateChanged,required TResult Function()  sessionRevoked,required TResult Function( PlatformInt64 count)  eventsLost,}) {final _that = this;
switch (_that) {
case CoreEvent_MessageReceived():
return messageReceived(_that.roomId,_that.message);case CoreEvent_RoomsChanged():
return roomsChanged();case CoreEvent_TimelineGap():
return timelineGap(_that.roomId);case CoreEvent_SyncStateChanged():
return syncStateChanged(_that.state);case CoreEvent_SessionRevoked():
return sessionRevoked();case CoreEvent_EventsLost():
return eventsLost(_that.count);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String roomId,  Message message)?  messageReceived,TResult? Function()?  roomsChanged,TResult? Function( String roomId)?  timelineGap,TResult? Function( SyncState state)?  syncStateChanged,TResult? Function()?  sessionRevoked,TResult? Function( PlatformInt64 count)?  eventsLost,}) {final _that = this;
switch (_that) {
case CoreEvent_MessageReceived() when messageReceived != null:
return messageReceived(_that.roomId,_that.message);case CoreEvent_RoomsChanged() when roomsChanged != null:
return roomsChanged();case CoreEvent_TimelineGap() when timelineGap != null:
return timelineGap(_that.roomId);case CoreEvent_SyncStateChanged() when syncStateChanged != null:
return syncStateChanged(_that.state);case CoreEvent_SessionRevoked() when sessionRevoked != null:
return sessionRevoked();case CoreEvent_EventsLost() when eventsLost != null:
return eventsLost(_that.count);case _:
  return null;

}
}

}

/// @nodoc


class CoreEvent_MessageReceived extends CoreEvent {
  const CoreEvent_MessageReceived({required this.roomId, required this.message}): super._();
  

 final  String roomId;
 final  Message message;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_MessageReceivedCopyWith<CoreEvent_MessageReceived> get copyWith => _$CoreEvent_MessageReceivedCopyWithImpl<CoreEvent_MessageReceived>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_MessageReceived&&(identical(other.roomId, roomId) || other.roomId == roomId)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,roomId,message);
}

@override
String toString() {
    return 'CoreEvent.messageReceived(roomId: $roomId, message: $message)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_MessageReceivedCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_MessageReceivedCopyWith(CoreEvent_MessageReceived value, $Res Function(CoreEvent_MessageReceived) _then) = _$CoreEvent_MessageReceivedCopyWithImpl;
@useResult
$Res call({
 String roomId, Message message
});




}
/// @nodoc
class _$CoreEvent_MessageReceivedCopyWithImpl<$Res>
    implements $CoreEvent_MessageReceivedCopyWith<$Res> {
  _$CoreEvent_MessageReceivedCopyWithImpl(this._self, this._then);

  final CoreEvent_MessageReceived _self;
  final $Res Function(CoreEvent_MessageReceived) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? roomId = null,Object? message = null,}) {
  return _then(CoreEvent_MessageReceived(
roomId: null == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as Message,
  ));
}


}

/// @nodoc


class CoreEvent_RoomsChanged extends CoreEvent {
  const CoreEvent_RoomsChanged(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_RoomsChanged);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'CoreEvent.roomsChanged()';
}


}




/// @nodoc


class CoreEvent_TimelineGap extends CoreEvent {
  const CoreEvent_TimelineGap({required this.roomId}): super._();
  

 final  String roomId;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_TimelineGapCopyWith<CoreEvent_TimelineGap> get copyWith => _$CoreEvent_TimelineGapCopyWithImpl<CoreEvent_TimelineGap>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_TimelineGap&&(identical(other.roomId, roomId) || other.roomId == roomId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,roomId);
}

@override
String toString() {
    return 'CoreEvent.timelineGap(roomId: $roomId)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_TimelineGapCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_TimelineGapCopyWith(CoreEvent_TimelineGap value, $Res Function(CoreEvent_TimelineGap) _then) = _$CoreEvent_TimelineGapCopyWithImpl;
@useResult
$Res call({
 String roomId
});




}
/// @nodoc
class _$CoreEvent_TimelineGapCopyWithImpl<$Res>
    implements $CoreEvent_TimelineGapCopyWith<$Res> {
  _$CoreEvent_TimelineGapCopyWithImpl(this._self, this._then);

  final CoreEvent_TimelineGap _self;
  final $Res Function(CoreEvent_TimelineGap) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? roomId = null,}) {
  return _then(CoreEvent_TimelineGap(
roomId: null == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CoreEvent_SyncStateChanged extends CoreEvent {
  const CoreEvent_SyncStateChanged({required this.state}): super._();
  

 final  SyncState state;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_SyncStateChangedCopyWith<CoreEvent_SyncStateChanged> get copyWith => _$CoreEvent_SyncStateChangedCopyWithImpl<CoreEvent_SyncStateChanged>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_SyncStateChanged&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode {
    return Object.hash(runtimeType,state);
}

@override
String toString() {
    return 'CoreEvent.syncStateChanged(state: $state)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_SyncStateChangedCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_SyncStateChangedCopyWith(CoreEvent_SyncStateChanged value, $Res Function(CoreEvent_SyncStateChanged) _then) = _$CoreEvent_SyncStateChangedCopyWithImpl;
@useResult
$Res call({
 SyncState state
});




}
/// @nodoc
class _$CoreEvent_SyncStateChangedCopyWithImpl<$Res>
    implements $CoreEvent_SyncStateChangedCopyWith<$Res> {
  _$CoreEvent_SyncStateChangedCopyWithImpl(this._self, this._then);

  final CoreEvent_SyncStateChanged _self;
  final $Res Function(CoreEvent_SyncStateChanged) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? state = null,}) {
  return _then(CoreEvent_SyncStateChanged(
state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as SyncState,
  ));
}


}

/// @nodoc


class CoreEvent_SessionRevoked extends CoreEvent {
  const CoreEvent_SessionRevoked(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_SessionRevoked);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'CoreEvent.sessionRevoked()';
}


}




/// @nodoc


class CoreEvent_EventsLost extends CoreEvent {
  const CoreEvent_EventsLost({required this.count}): super._();
  

 final  PlatformInt64 count;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_EventsLostCopyWith<CoreEvent_EventsLost> get copyWith => _$CoreEvent_EventsLostCopyWithImpl<CoreEvent_EventsLost>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_EventsLost&&(identical(other.count, count) || other.count == count));
}


@override
int get hashCode {
    return Object.hash(runtimeType,count);
}

@override
String toString() {
    return 'CoreEvent.eventsLost(count: $count)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_EventsLostCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_EventsLostCopyWith(CoreEvent_EventsLost value, $Res Function(CoreEvent_EventsLost) _then) = _$CoreEvent_EventsLostCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 count
});




}
/// @nodoc
class _$CoreEvent_EventsLostCopyWithImpl<$Res>
    implements $CoreEvent_EventsLostCopyWith<$Res> {
  _$CoreEvent_EventsLostCopyWithImpl(this._self, this._then);

  final CoreEvent_EventsLost _self;
  final $Res Function(CoreEvent_EventsLost) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? count = null,}) {
  return _then(CoreEvent_EventsLost(
count: null == count ? _self.count : count // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

// dart format on
