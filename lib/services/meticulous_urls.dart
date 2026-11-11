// Addresses on a Meticulous machine. Profile IDs and image paths come from
// the machine's profile list, which holds whatever a shared profile file put
// there. The machine runs actions such as preheat on a plain GET, so such a
// value must never be able to point a request somewhere else.

final _plainSegment = RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9._-]*$');
final _profileImage = RegExp(
  r'^/api/v1/profile/image/[A-Za-z0-9_-][A-Za-z0-9._-]*$',
);

bool isPlainPathSegment(String id) => _plainSegment.hasMatch(id);

/// [id] if it can stand as one segment of a URL path, otherwise an
/// [ArgumentError]. Profile IDs are UUIDs.
String plainPathSegment(String id) {
  if (!_plainSegment.hasMatch(id)) {
    throw ArgumentError.value(id, 'id', 'not a plain ID');
  }
  return id;
}

/// Whether [path] is a profile image on the machine. Anything else, an action
/// endpoint or a path that changes the host, is not fetched.
bool isProfileImagePath(String? path) =>
    path != null && _profileImage.hasMatch(path);

/// The URL of a profile image on [host], or null if [path] is not one.
Uri? profileImageUri(String host, String? path) =>
    isProfileImagePath(path) ? Uri.parse('http://$host$path') : null;
