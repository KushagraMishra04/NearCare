import 'package:flutter_test/flutter_test.dart';
import 'package:carenear/main.dart';
import 'package:latlong2/latlong.dart' hide Path;

void main() {
  test('AppState initializes with default location and doctors with coordinates', () {
    final state = AppState();
    expect(state.userLocation, equals(const LatLng(28.6360, 77.3688)));
    expect(state.docs.isNotEmpty, isTrue);

    for (final doc in state.docs) {
      expect(doc.lat, isNotNull);
      expect(doc.lng, isNotNull);
      expect(doc.latLng.latitude, equals(doc.lat));
      expect(doc.latLng.longitude, equals(doc.lng));
      expect(doc.address.isNotEmpty, isTrue);
      expect(doc.phone.isNotEmpty, isTrue);
    }
  });

  test('Filtering by specialty returns matching doctors', () {
    final state = AppState();
    state.spec = 'Cardiology';
    final cardiologyDocs = state.list();
    expect(cardiologyDocs.every((d) => d.spec == 'Cardiology'), isTrue);
  });
}
