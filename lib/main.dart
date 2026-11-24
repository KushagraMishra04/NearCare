import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

const bool kGuest = true; // dev shortcut: set false to remove guest mode

const pine = Color(0xFF0F4C47), mint = Color(0xFFD6EFE8), coral = Color(0xFFF2684A);
const ink = Color(0xFF12302E), mute = Color(0xFF5E7270), line = Color(0xFFDCE5E2);
const bgc = Color(0xFFEEF2F0), warnC = Color(0xFFFFF1D6), adm = Color(0xFF1B2433), admAcc = Color(0xFF7C9CFF);
const errC = Color(0xFFD9472B), admMute = Color(0xFF9AA8C2), admField = Color(0xFF232E42), admLine = Color(0xFF33415C);

Future<void> openExternalUrl(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

// ───────────────────────── Data & state ─────────────────────────
class Doc {
  final String name, spec, fac, address, phone;
  double dist;
  final double rating;
  final int fee;
  final List<String> slots;
  final Set<int> taken;
  final Offset pos;
  final double lat, lng;

  Doc(
    this.name,
    this.spec,
    this.fac,
    this.dist,
    this.fee,
    this.rating,
    this.slots,
    this.taken,
    this.pos, {
    required this.lat,
    required this.lng,
    this.address = 'Indirapuram, Ghaziabad',
    this.phone = '+91 98765 43210',
  });

  LatLng get latLng => LatLng(lat, lng);
  String get initials {
    final p = name.split(' ');
    return p[1][0] + (p.length > 2 ? p[2][0] : '');
  }
  int get free => slots.length - taken.length;
}

class Appt { int doc; String time, st; Appt(this.doc, this.time, this.st); }
class Req { String p, d, t, st; Req(this.p, this.d, this.t, this.st); }
class Rev { String p, t, st; Rev(this.p, this.t, this.st); }
class AdmDoc { String name; bool on, v; AdmDoc(this.name, this.on, this.v); }

enum Scr { welcome, plog, alog, pat, adm }

const specs = ['All', 'Cardiology', 'General Physician', 'Dermatology', 'Pediatrics', 'Neurology'];
const kw = {
  'chest': 'Cardiology', 'heart': 'Cardiology', 'skin': 'Dermatology', 'rash': 'Dermatology',
  'child': 'Pediatrics', 'baby': 'Pediatrics', 'headache': 'Neurology', 'migraine': 'Neurology',
  'fever': 'General Physician', 'cold': 'General Physician',
};

class AppState extends ChangeNotifier {
  Scr scr = Scr.welcome;
  String tab = 'home', spec = 'All', hint = '', sort = 'best';
  int? doc, slot;
  bool urgent = false;
  final symC = TextEditingController();

  static const LatLng defaultLocation = LatLng(28.6360, 77.3688); // Indirapuram, Ghaziabad
  LatLng userLocation = defaultLocation;
  bool isLiveGps = false;
  bool isLocating = false;
  String? locationStatusMessage;
  String locationLabel = 'Indirapuram, Ghaziabad';

  final docs = [
    Doc('Dr. Aarti Sharma', 'Cardiology', 'Sunrise Heart Clinic', 1.8, 700, 4.7, ['10:00', '11:30', '16:00'], {1}, const Offset(.42, .40),
        lat: 28.6410, lng: 77.3735, address: 'Plot 14, Ahinsa Khand 2, Indirapuram', phone: '+91 98111 22334'),
    Doc('Dr. Rohan Mehta', 'General Physician', 'CityCare Hospital', 0.9, 400, 4.4, ['09:30', '12:00', '17:30'], {}, const Offset(.62, .55),
        lat: 28.6335, lng: 77.3640, address: 'Sector 4, Vaishali / Indirapuram Border', phone: '+91 98222 33445'),
    Doc('Dr. Neha Kapoor', 'Dermatology', 'SkinFirst Clinic', 3.2, 600, 4.6, ['11:00', '14:30', '15:30'], {0}, const Offset(.25, .65),
        lat: 28.6250, lng: 77.3820, address: 'Near Swarna Jayanti Park, Indirapuram', phone: '+91 98333 44556'),
    Doc('Dr. Imran Khan', 'Pediatrics', 'Little Steps Clinic', 2.4, 500, 4.8, ['10:30', '13:00', '18:00'], {}, const Offset(.75, .30),
        lat: 28.6480, lng: 77.3610, address: 'Gyan Khand 1, Indirapuram', phone: '+91 98444 55667'),
    Doc('Dr. Vikram Rao', 'Neurology', 'CityCare Hospital', 0.9, 900, 4.5, ['12:30', '16:30', '17:00'], {2}, const Offset(.58, .72),
        lat: 28.6335, lng: 77.3640, address: 'Sector 4, Vaishali / Indirapuram Border', phone: '+91 98555 66778'),
  ];
  final appts = [Appt(1, 'Tomorrow, 12:00', 'confirmed')];
  final reqs = [
    Req('Priya N.', 'Dr. Sharma', 'Today 16:00', 'requested'),
    Req('Amit K.', 'Dr. Mehta', 'Today 17:30', 'requested'),
    Req('Sana R.', 'Dr. Kapoor', 'Tomorrow 11:00', 'confirmed'),
  ];
  final revs = [Rev('Anon user', 'Great doctor, short wait.', 'pending'), Rev('Demo user', 'Rude reception!!!', 'pending')];
  late final admDocs = [for (var i = 0; i < docs.length; i++) AdmDoc(docs[i].name, true, i < 3)];

  void go(Scr s, {String? t}) { scr = s; doc = null; if (t != null) tab = t; notifyListeners(); }
  void set(VoidCallback f) { f(); notifyListeners(); }

  Future<bool> fetchUserLocation({BuildContext? context}) async {
    isLocating = true;
    locationStatusMessage = 'Acquiring GPS location...';
    notifyListeners();

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        locationStatusMessage = 'Location services disabled. Please enable device GPS.';
        isLocating = false;
        notifyListeners();
        if (context != null && context.mounted) {
          say(context, 'Please turn on GPS / Location services');
        }
        return false;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          locationStatusMessage = 'Location permission denied.';
          isLocating = false;
          notifyListeners();
          if (context != null && context.mounted) {
            say(context, 'Location permission denied');
          }
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        locationStatusMessage = 'Location permission permanently denied. Enable in app settings.';
        isLocating = false;
        notifyListeners();
        if (context != null && context.mounted) {
          say(context, 'Location permission permanently denied');
        }
        return false;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );

      userLocation = LatLng(pos.latitude, pos.longitude);
      isLiveGps = true;
      locationLabel = 'Live GPS (${pos.latitude.toStringAsFixed(3)}, ${pos.longitude.toStringAsFixed(3)})';
      locationStatusMessage = null;

      // Recalculate distances to all doctors based on real coordinates
      for (final d in docs) {
        final meters = Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          d.lat,
          d.lng,
        );
        d.dist = double.parse((meters / 1000.0).toStringAsFixed(1));
      }

      isLocating = false;
      notifyListeners();
      if (context != null && context.mounted) {
        say(context, 'Location updated! Distances recalculated.');
      }
      return true;
    } catch (e) {
      locationStatusMessage = 'Failed to fetch GPS location: $e';
      isLocating = false;
      notifyListeners();
      if (context != null && context.mounted) {
        say(context, 'Could not acquire GPS: $e');
      }
      return false;
    }
  }

  int score(Doc x) {
    final base = ((spec != 'All' && x.spec == spec) || hint == x.spec) ? 30 : 10;
    return (base + (5 - x.dist) * 5 + x.free * 6 + (900 - x.fee) / 90 + x.rating * 2).round();
  }

  String why(Doc x) {
    final a = <String>[if (hint == x.spec) 'matches suggested specialty', '${x.dist} km away', '${x.free} slots today', 'fee ₹${x.fee}'];
    return 'Ranked because: ${a.join(', ')}';
  }

  List<Doc> list() {
    final l = docs.where((x) => spec == 'All' || x.spec == spec).toList();
    l.sort((a, b) => sort == 'dist' ? a.dist.compareTo(b.dist) : sort == 'fee' ? a.fee.compareTo(b.fee) : score(b).compareTo(score(a)));
    return l;
  }

  void suggest() {
    final v = symC.text.toLowerCase();
    hint = 'General Physician';
    urgent = RegExp('chest|breath|faint').hasMatch(v);
    for (final k in kw.keys) { if (v.contains(k)) { hint = kw[k]!; break; } }
    spec = hint;
    notifyListeners();
  }
}

final app = AppState();

void say(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(
    content: Text(m, textAlign: TextAlign.center), behavior: SnackBarBehavior.floating,
    backgroundColor: ink, duration: const Duration(milliseconds: 1800)));

// ───────────────────────── Shared widgets ─────────────────────────
class Head extends StatelessWidget {
  final Widget child; final bool admin; final double top, bottom;
  const Head(this.child, {this.admin = false, this.top = 28, this.bottom = 24, super.key});
  @override
  Widget build(BuildContext c) => Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(20, top + MediaQuery.of(c).padding.top, 20, bottom),
        decoration: BoxDecoration(color: admin ? adm : pine, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28))),
        child: DefaultTextStyle.merge(style: const TextStyle(color: Colors.white), child: child),
      );
}

Widget backBtn(VoidCallback f, {Color color = Colors.white}) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton(onPressed: f, style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36), foregroundColor: color), child: const Text('← Back')));

class Btn extends StatelessWidget {
  final String t; final VoidCallback? onTap; final int kind; final bool small; final Color? bg, fg, border; final double opacity;
  const Btn(this.t, this.onTap, {this.kind = 0, this.small = false, this.bg, this.fg, this.border, this.opacity = 1, super.key});
  @override
  Widget build(BuildContext c) {
    final fill = kind == 0 ? (bg ?? coral) : kind == 1 ? mint : Colors.transparent;
    final txt = fg ?? (kind == 0 ? Colors.white : kind == 1 ? pine : ink);
    final r = BorderRadius.circular(small ? 10 : 12);
    return Opacity(
      opacity: opacity,
      child: SizedBox(
        width: small ? null : double.infinity,
        child: Material(
          color: fill, borderRadius: r,
          child: InkWell(
            borderRadius: r, onTap: onTap,
            child: Container(
              alignment: small ? null : Alignment.center,
              padding: EdgeInsets.symmetric(vertical: small ? 8 : 13, horizontal: small ? 14 : 0),
              decoration: (kind == 2 || border != null) ? BoxDecoration(border: Border.all(color: border ?? line), borderRadius: r) : null,
              child: Text(t, style: TextStyle(color: txt, fontWeight: FontWeight.w600, fontSize: small ? 13 : 15)),
            ),
          ),
        ),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final String t, k;
  const Pill(this.t, {this.k = '', super.key});
  @override
  Widget build(BuildContext c) {
    Color bg = mint, fg = pine;
    if (k == 'r') { bg = const Color(0xFFFDE3DC); fg = const Color(0xFFA33A22); }
    if (k == 'y') { bg = warnC; fg = const Color(0xFF7A5A00); }
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Text(t, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)));
  }
}

class CardBox extends StatelessWidget {
  final Widget child; final VoidCallback? onTap;
  const CardBox({required this.child, this.onTap, super.key});
  @override
  Widget build(BuildContext c) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: line), borderRadius: BorderRadius.circular(16)),
        child: InkWell(borderRadius: BorderRadius.circular(16), onTap: onTap, child: Padding(padding: const EdgeInsets.all(12), child: child)),
      );
}

Widget note(Widget child, {Color bg = warnC, double top = 8}) => Container(
    width: double.infinity, margin: EdgeInsets.only(top: top, bottom: 8), padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)), child: DefaultTextStyle.merge(style: const TextStyle(fontSize: 12, height: 1.4), child: child));

Widget h3(String s) => Padding(padding: const EdgeInsets.only(top: 14, bottom: 8), child: Text(s, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)));
Widget mt(String s, {Color color = mute}) => Text(s, style: TextStyle(color: color, fontSize: 13));
Widget title(String s) => Text(s, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700));
Widget gap(double h) => SizedBox(height: h);
Widget avatar(String s) => Container(width: 44, height: 44, alignment: Alignment.center, decoration: BoxDecoration(color: mint, borderRadius: BorderRadius.circular(12)),
    child: Text(s, style: const TextStyle(color: pine, fontWeight: FontWeight.w700)));

Widget fld(String label, TextEditingController c, String hint,
    {String? err, bool pw = false, bool show = false, VoidCallback? toggle, TextInputType? kb, int? max, bool dark = false, ValueChanged<String>? onChanged}) {
  final bc = err != null ? errC : (dark ? admLine : line);
  OutlineInputBorder ob() => OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: bc));
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: TextStyle(fontSize: 12, color: dark ? admMute : mute)),
    gap(4),
    TextField(
      controller: c, obscureText: pw && !show, keyboardType: kb, maxLength: max, onChanged: onChanged,
      style: TextStyle(color: dark ? Colors.white : ink),
      decoration: InputDecoration(
        hintText: hint, counterText: '', isDense: true, filled: true, fillColor: dark ? admField : Colors.white,
        contentPadding: const EdgeInsets.all(12), border: ob(), enabledBorder: ob(), focusedBorder: ob(),
        suffixIcon: pw ? TextButton(onPressed: toggle, child: Text(show ? 'Hide' : 'Show', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: dark ? admAcc : pine))) : null,
      ),
    ),
    if (err != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(err, style: const TextStyle(color: errC, fontSize: 12))),
    gap(10),
  ]);
}

Widget checkRow(bool v, ValueChanged<bool?>? f, Widget label, {bool dark = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [SizedBox(width: 24, height: 24, child: Checkbox(value: v, onChanged: f, activeColor: dark ? admAcc : pine)), const SizedBox(width: 8), Expanded(child: label)]));

// ───────────────────────── App root ─────────────────────────
void main() => runApp(const CareNearApp());

class CareNearApp extends StatelessWidget {
  const CareNearApp({super.key});
  @override
  Widget build(BuildContext c) => MaterialApp(
        title: 'CareNear', debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: pine), scaffoldBackgroundColor: Colors.white,
          textTheme: ThemeData.light().textTheme.apply(bodyColor: ink, displayColor: ink),
        ),
        builder: (c, child) => Container(color: bgc, child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: child))),
        home: const Root(),
      );
}

class Root extends StatelessWidget {
  const Root({super.key});
  @override
  Widget build(BuildContext c) => AnimatedBuilder(
      animation: app,
      builder: (c, _) {
        final a = app;
        Widget body;
        if (a.scr == Scr.welcome) {
          body = const Welcome();
        } else if (a.scr == Scr.plog) {
          body = const PLogin();
        } else if (a.scr == Scr.alog) {
          body = const ALogin();
        } else if (a.scr == Scr.adm) {
          body = const Admin();
        } else if (a.doc != null) {
          body = const Profile();
        } else if (a.tab == 'map') {
          body = const MapTab();
        } else if (a.tab == 'visits') {
          body = const Visits();
        } else if (a.tab == 'rec') {
          body = const Records();
        } else {
          body = const Home();
        }
        Widget? nav;
        if (a.scr == Scr.pat && a.doc == null) {
          const t = ['home', 'map', 'visits', 'rec'];
          nav = BottomNavigationBar(
            type: BottomNavigationBarType.fixed, backgroundColor: Colors.white, selectedItemColor: pine, unselectedItemColor: mute, selectedFontSize: 11, unselectedFontSize: 11,
            currentIndex: t.indexOf(a.tab).clamp(0, 3).toInt(), onTap: (i) => a.set(() => a.tab = t[i]),
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
              BottomNavigationBarItem(icon: Icon(Icons.map_outlined), label: 'Map'),
              BottomNavigationBarItem(icon: Icon(Icons.calendar_month_outlined), label: 'Visits'),
              BottomNavigationBarItem(icon: Icon(Icons.description_outlined), label: 'Records'),
            ],
          );
        } else if (a.scr == Scr.adm) {
          const t = ['dash', 'prov', 'bk', 'rv'];
          nav = BottomNavigationBar(
            type: BottomNavigationBarType.fixed, backgroundColor: Colors.white, selectedItemColor: admAcc, unselectedItemColor: mute, selectedFontSize: 11, unselectedFontSize: 11,
            currentIndex: t.indexOf(a.tab).clamp(0, 3).toInt(), onTap: (i) => a.set(() => a.tab = t[i]),
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), label: 'Home'),
              BottomNavigationBarItem(icon: Icon(Icons.medical_services_outlined), label: 'Doctors'),
              BottomNavigationBarItem(icon: Icon(Icons.event_note_outlined), label: 'Bookings'),
              BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline), label: 'Reviews'),
            ],
          );
        }
        final isFullView = a.scr == Scr.pat && a.doc == null && a.tab == 'map';
        return Scaffold(
          backgroundColor: a.scr == Scr.alog ? adm : Colors.white,
          bottomNavigationBar: nav,
          body: isFullView
              ? body
              : SingleChildScrollView(key: ValueKey('${a.scr}${a.tab}${a.doc}'), child: body),
        );
      });
}

// ───────────────────────── Welcome & logins ─────────────────────────
class Welcome extends StatelessWidget {
  const Welcome({super.key});
  @override
  Widget build(BuildContext c) => Column(children: [
        const Head(top: 60, bottom: 40, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('CareNear', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
          SizedBox(height: 6),
          Text('Find a doctor nearby. Book in a minute.', style: TextStyle(color: Colors.white70)),
        ])),
        Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          h3('Continue as'),
          Btn('I’m a patient', () => app.go(Scr.plog)),
          gap(10),
          Btn('I run a clinic or hospital', () => app.go(Scr.alog), kind: 2),
          gap(20),
          note(const Text('Demo build with sample doctors and slots. CareNear suggests specialties; it does not diagnose.')),
        ])),
      ]);
}

class PLogin extends StatefulWidget {
  const PLogin({super.key});
  @override
  State<PLogin> createState() => _PLoginState();
}

class _PLoginState extends State<PLogin> {
  bool up = false, show = false, load = false, tos = false, rem = true;
  final err = <String, String>{};
  final nm = TextEditingController(), em = TextEditingController(), pw = TextEditingController(), pw2 = TextEditingController();

  @override
  void dispose() { nm.dispose(); em.dispose(); pw.dispose(); pw2.dispose(); super.dispose(); }

  void clr(String k) { if (err.containsKey(k)) setState(() => err.remove(k)); }

  void submit() {
    final e = <String, String>{};
    final v = em.text.trim();
    if (up && nm.text.trim().isEmpty) e['nm'] = 'Enter your name';
    if (v.isEmpty) {
      e['em'] = 'Enter your email or mobile number';
    } else if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(v) && v.replaceAll(RegExp(r'\D'), '').length != 10) {
      e['em'] = 'Use a valid email or 10-digit mobile number';
    }
    if (pw.text.length < (up ? 8 : 6)) e['pw'] = up ? 'Use at least 8 characters' : 'Password must be at least 6 characters';
    if (up && pw2.text != pw.text) e['pw2'] = 'Passwords do not match';
    if (up && !tos) e['tos'] = 'Accept the terms to continue';
    setState(() { err..clear()..addAll(e); });
    if (e.isNotEmpty) return;
    setState(() => load = true);
    Future.delayed(const Duration(milliseconds: 900), () { if (mounted) app.go(Scr.pat, t: 'home'); });
  }

  Widget seg(String t, bool on, VoidCallback f) => Expanded(
      child: GestureDetector(onTap: f, child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9), alignment: Alignment.center,
          decoration: BoxDecoration(color: on ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(9),
              boxShadow: on ? const [BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))] : null),
          child: Text(t, style: TextStyle(fontWeight: FontWeight.w600, color: on ? ink : mute)))));

  @override
  Widget build(BuildContext c) => Column(children: [
        Head(top: 28, bottom: 20, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          backBtn(() => app.go(Scr.welcome)),
          const Text('CareNear', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          gap(8),
          Text(up ? 'Create your account' : 'Welcome back', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          gap(6),
          Text(up ? 'It takes under a minute.' : 'Sign in to find care near you.', style: const TextStyle(color: Colors.white70)),
        ])),
        Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(4), margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: bgc, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [seg('Sign in', !up, () => setState(() { up = false; err.clear(); })), seg('Create account', up, () => setState(() { up = true; err.clear(); }))]),
          ),
          if (up) fld('Full name', nm, 'e.g. Priya Nair', err: err['nm'], onChanged: (_) => clr('nm')),
          fld('Email or mobile number', em, 'you@example.com or 98XXXXXXXX', err: err['em'], onChanged: (_) => clr('em')),
          fld(up ? 'Create password' : 'Password', pw, up ? 'At least 8 characters' : 'Your password', pw: true, show: show, toggle: () => setState(() => show = !show), err: err['pw'], onChanged: (_) => clr('pw')),
          if (up) fld('Confirm password', pw2, 'Re-enter password', pw: true, show: show, toggle: () => setState(() => show = !show), err: err['pw2'], onChanged: (_) => clr('pw2')),
          if (up) ...[
            checkRow(tos, (v) => setState(() { tos = v ?? false; err.remove('tos'); }), const Text('I agree to the Terms and Privacy Policy', style: TextStyle(fontSize: 13))),
            if (err['tos'] != null) Text(err['tos']!, style: const TextStyle(color: errC, fontSize: 12)),
          ] else
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(child: checkRow(rem, (v) => setState(() => rem = v ?? false), const Text('Keep me signed in', style: TextStyle(fontSize: 13)))),
              GestureDetector(onTap: () => say(c, 'Reset link sent (demo)'), child: const Text('Forgot password?', style: TextStyle(fontSize: 13, color: pine, fontWeight: FontWeight.w700))),
            ]),
          gap(6),
          Btn(load ? 'Please wait…' : up ? 'Create account' : 'Sign in', load ? null : submit, opacity: load ? .7 : 1),
          Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Row(children: const [
            Expanded(child: Divider(color: line)), Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('or', style: TextStyle(color: mute, fontSize: 12))), Expanded(child: Divider(color: line))])),
          Btn('Get a one-time code by SMS', () => say(c, 'One-time code sent (demo)'), kind: 2),
          gap(8),
          Btn('Continue with Google', () => say(c, 'Google sign-in (demo)'), kind: 2),
          if (kGuest) ...[gap(12), Btn('Continue as guest (dev)', () => app.go(Scr.pat, t: 'home'), kind: 1, border: pine)],
          note(const Text('We ask for your location only when you search. You can type an area or PIN code instead.'), top: 16),
          const Center(child: Text('Demo build · any valid-looking details will work', style: TextStyle(color: mute, fontSize: 11))),
        ])),
      ]);
}

class ALogin extends StatefulWidget {
  const ALogin({super.key});
  @override
  State<ALogin> createState() => _ALoginState();
}

class _ALoginState extends State<ALogin> {
  int step = 1, fails = 0;
  bool show = false;
  final err = <String, String>{};
  final id = TextEditingController(text: 'CC-0042'), em = TextEditingController(), pw = TextEditingController(), otp = TextEditingController();

  @override
  void dispose() { id.dispose(); em.dispose(); pw.dispose(); otp.dispose(); super.dispose(); }

  void clr(String k) { if (err.containsKey(k)) setState(() => err.remove(k)); }

  void submit() {
    final e = <String, String>{};
    if (step == 1) {
      if (!RegExp(r'^[A-Za-z]{2}-\d{4}$').hasMatch(id.text.trim())) e['id'] = 'Facility IDs look like CC-0042';
      if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(em.text.trim())) e['em'] = 'Enter your work email';
      if (pw.text.length < 6) e['pw'] = 'Password must be at least 6 characters';
      setState(() { err..clear()..addAll(e); if (e.isEmpty) step = 2; });
    } else {
      if (!RegExp(r'^\d{6}$').hasMatch(otp.text)) {
        setState(() { fails++; err['otp'] = 'Enter the 6 digits from your app (${3 - fails} tries left)'; });
        return;
      }
      app.go(Scr.adm, t: 'dash');
    }
  }

  @override
  Widget build(BuildContext c) {
    final s2 = step == 2;
    return SafeArea(
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Color(0xFFE8EDF7)),
        child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          backBtn(() => s2 ? setState(() { step = 1; err.clear(); }) : app.go(Scr.welcome), color: const Color(0xFFE8EDF7)),
          gap(8),
          Container(width: 52, height: 52, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFF2A3650), borderRadius: BorderRadius.circular(16)), child: const Text('🛡️', style: TextStyle(fontSize: 24))),
          gap(14),
          Text(s2 ? 'Verify it’s you' : 'Clinic admin sign-in', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
          gap(6),
          mt(s2 ? 'Enter the 6-digit code from your authenticator app.' : 'For hospital and clinic staff. Every action is logged.', color: admMute),
          Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Row(children: [
            for (final on in [true, s2]) Expanded(child: Container(height: 4, margin: const EdgeInsets.only(right: 3, left: 3), decoration: BoxDecoration(color: on ? admAcc : admLine, borderRadius: BorderRadius.circular(4)))),
          ])),
          if (fails >= 3)
            note(const Text('Too many wrong codes. Sign-in is paused for 15 minutes. Contact your super admin.', style: TextStyle(color: Color(0xFF7A5A00))))
          else if (s2) ...[
            fld('Authentication code', otp, '000000', kb: TextInputType.number, max: 6, dark: true, err: err['otp'], onChanged: (_) => clr('otp')),
            Btn('Verify and open portal', submit, bg: admAcc, fg: const Color(0xFF111111)),
            gap(10),
            Center(child: mt('Demo: any 6 digits work.', color: admMute)),
          ] else ...[
            fld('Facility ID', id, 'e.g. CC-0042', dark: true, err: err['id'], onChanged: (_) => clr('id')),
            fld('Work email', em, 'name@hospital.org', dark: true, kb: TextInputType.emailAddress, err: err['em'], onChanged: (_) => clr('em')),
            fld('Password', pw, 'Your password', pw: true, show: show, toggle: () => setState(() => show = !show), dark: true, err: err['pw'], onChanged: (_) => clr('pw')),
            checkRow(true, null, const Text('Sign out automatically after 30 minutes idle', style: TextStyle(fontSize: 13)), dark: true),
            Btn('Continue', submit, bg: admAcc, fg: const Color(0xFF111111)),
            gap(14),
            Center(child: Column(children: [
              mt('Forgot password? Contact your super admin.', color: admMute),
              gap(4),
              GestureDetector(onTap: () => say(c, 'Access request form (demo)'), child: const Text('Request facility access', style: TextStyle(color: admAcc, fontWeight: FontWeight.w700))),
            ])),
          ],
          if (kGuest) ...[gap(14), Btn('Continue as guest admin (dev)', () => app.go(Scr.adm, t: 'dash'), kind: 2, fg: const Color(0xFFE8EDF7), border: const Color(0xFF5A6B8C))],
          gap(8),
          Center(child: mt('Demo build · sample data only', color: admMute)),
        ])),
      ),
    );
  }
}

// ───────────────────────── Patient screens ─────────────────────────
Widget docCard(Doc x) => CardBox(
      onTap: () => app.set(() { app.doc = app.docs.indexOf(x); app.slot = null; }),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          avatar(x.initials), const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(x.name, style: const TextStyle(fontWeight: FontWeight.w700)), mt('${x.spec} · ${x.fac}')])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text('★ ${x.rating}', style: const TextStyle(fontWeight: FontWeight.w700)), mt('${x.dist} km')]),
        ]),
        note(Text(app.why(x)), bg: mint),
      ]),
    );

class Home extends StatelessWidget {
  const Home({super.key});
  @override
  Widget build(BuildContext c) {
    final a = app;
    final l = a.list();
    return Column(children: [
      Head(top: 20, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
            child: GestureDetector(
              onTap: () => a.fetchUserLocation(context: c),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Searching near (tap for live GPS)', style: TextStyle(fontSize: 12, color: Colors.white70)),
                const SizedBox(height: 2),
                Row(children: [
                  Flexible(child: Text(a.locationLabel, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white), overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 6),
                  if (a.isLocating)
                    const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  else
                    const Icon(Icons.my_location, size: 14, color: Colors.white70),
                ]),
              ]),
            ),
          ),
          const Pill('5 km'),
        ]),
        gap(16),
        _SymField(),
        gap(8),
        Btn('Suggest a specialty', a.suggest),
      ])),
      Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (a.hint.isNotEmpty)
          note(Text.rich(TextSpan(children: [
            const TextSpan(text: 'Suggestion: consider a '),
            TextSpan(text: a.hint, style: const TextStyle(fontWeight: FontWeight.w700)),
            const TextSpan(text: ' specialist. This is not a diagnosis. '),
            if (a.urgent) const TextSpan(text: 'If symptoms are severe or sudden, call emergency services (112) now.', style: TextStyle(fontWeight: FontWeight.w700)),
          ]))),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
          for (final s in specs)
            Padding(padding: const EdgeInsets.only(right: 8), child: GestureDetector(
              onTap: () => a.set(() => a.spec = s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(color: a.spec == s ? pine : Colors.white, border: Border.all(color: a.spec == s ? pine : line), borderRadius: BorderRadius.circular(99)),
                child: Text(s, style: TextStyle(fontSize: 13, color: a.spec == s ? Colors.white : ink))))),
        ])),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          mt('Sort by'),
          DropdownButton<String>(
            value: a.sort, underline: const SizedBox(), style: const TextStyle(color: ink, fontSize: 14), onChanged: (v) => a.set(() => a.sort = v!),
            items: const [DropdownMenuItem(value: 'best', child: Text('Best match')), DropdownMenuItem(value: 'dist', child: Text('Distance')), DropdownMenuItem(value: 'fee', child: Text('Lowest fee'))]),
        ]),
        if (l.isEmpty) mt('No providers within 5 km. Try a wider radius.') else ...l.map(docCard),
      ])),
    ]);
  }
}

// Dark-on-pine symptom box (plain field styled for the hero)
class _SymField extends StatelessWidget {
  @override
  Widget build(BuildContext c) => TextField(
        controller: app.symC, style: const TextStyle(color: ink),
        decoration: InputDecoration(hintText: 'Describe your concern, e.g. chest pain', filled: true, fillColor: Colors.white, isDense: true, contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)),
      );
}

class MapTab extends StatefulWidget {
  const MapTab({super.key});

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> {
  final MapController _mapController = MapController();
  Doc? _selectedDoc;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!app.isLiveGps && !app.isLocating) {
        app.fetchUserLocation(context: context);
      }
    });
  }

  void _moveTo(LatLng point, double zoom) {
    _mapController.move(point, zoom);
  }

  void _recenterToAllDocs() {
    if (app.docs.isEmpty) return;
    final latLngs = [app.userLocation, ...app.docs.map((d) => d.latLng)];
    final bounds = LatLngBounds.fromPoints(latLngs);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 80),
      ),
    );
  }

  IconData _specIcon(String spec) {
    switch (spec) {
      case 'Cardiology':
        return Icons.favorite_rounded;
      case 'General Physician':
        return Icons.medical_services_rounded;
      case 'Dermatology':
        return Icons.face_rounded;
      case 'Pediatrics':
        return Icons.child_care_rounded;
      case 'Neurology':
        return Icons.psychology_rounded;
      default:
        return Icons.local_hospital_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = app;
    final filteredDocs = a.list();

    return LayoutBuilder(
      builder: (context, constraints) {
        final double h = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.of(context).size.height - kBottomNavigationBarHeight - MediaQuery.of(context).padding.top;
        final double w = constraints.maxWidth.isFinite ? constraints.maxWidth : MediaQuery.of(context).size.width;

        return SizedBox(
          width: w,
          height: h,
          child: Stack(
            children: [
          // 1. FlutterMap OpenStreetMap
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: a.userLocation,
              initialZoom: 14.0,
              minZoom: 4,
              maxZoom: 18,
              onTap: (tapPosition, point) {
                if (_selectedDoc != null) {
                  setState(() => _selectedDoc = null);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.carenear.app',
                maxZoom: 19,
              ),
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: a.userLocation,
                    color: const Color(0x332A6BFF),
                    borderColor: const Color(0xFF2A6BFF),
                    borderStrokeWidth: 2,
                    radius: 36,
                  ),
                ],
              ),
              if (_selectedDoc != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [a.userLocation, _selectedDoc!.latLng],
                      color: pine,
                      strokeWidth: 3.0,
                      pattern: StrokePattern.dashed(segments: const [8, 5]),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  // User Location Pin
                  Marker(
                    point: a.userLocation,
                    width: 60,
                    height: 60,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A6BFF),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                          ),
                          child: const Text('You', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A6BFF),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
                          ),
                          child: const Icon(Icons.navigation_rounded, size: 12, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  // Doctor Pins
                  for (final d in filteredDocs)
                    Marker(
                      point: d.latLng,
                      width: 140,
                      height: 56,
                      alignment: Alignment.bottomCenter,
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _selectedDoc = d);
                          _moveTo(d.latLng, 15.2);
                        },
                        child: AnimatedScale(
                          duration: const Duration(milliseconds: 200),
                          scale: _selectedDoc == d ? 1.15 : 1.0,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                constraints: const BoxConstraints(maxWidth: 130),
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _selectedDoc == d ? pine : coral,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white, width: 2),
                                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 5, offset: Offset(0, 2))],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(_specIcon(d.spec), color: Colors.white, size: 12),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        d.spec.split(' ').first,
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (_selectedDoc == d) ...[
                                      const SizedBox(width: 3),
                                      const Icon(Icons.check_circle_rounded, color: Colors.white, size: 11),
                                    ],
                                  ],
                                ),
                              ),
                              CustomPaint(
                                size: const Size(10, 6),
                                painter: _PinTrianglePainter(color: _selectedDoc == d ? pine : coral),
                              ),
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: _selectedDoc == d ? pine : Colors.black87,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 1.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // 2. Top Header Overlay
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 8, 16, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.96),
                    Colors.white.withValues(alpha: 0.90),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.75, 1.0],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Doctor Map', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ink)),
                          Row(
                            children: [
                              Icon(
                                a.isLiveGps ? Icons.gps_fixed_rounded : Icons.location_on_outlined,
                                size: 13,
                                color: a.isLiveGps ? const Color(0xFF2A6BFF) : mute,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                a.locationLabel,
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: a.isLiveGps ? const Color(0xFF2A6BFF) : mute),
                              ),
                            ],
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        onPressed: a.isLocating ? null : () => a.fetchUserLocation(context: context).then((_) {
                          _moveTo(a.userLocation, 14.5);
                        }),
                        icon: a.isLocating
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: pine))
                            : const Icon(Icons.my_location, size: 15),
                        label: Text(a.isLocating ? 'Locating...' : 'My GPS'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: mint,
                          foregroundColor: pine,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final s in specs)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Builder(builder: (context) {
                              final count = s == 'All' ? a.docs.length : a.docs.where((x) => x.spec == s).length;
                              return ChoiceChip(
                                label: Text('$s ($count)'),
                                selected: a.spec == s,
                                onSelected: (selected) {
                                  if (selected) {
                                    a.set(() => a.spec = s);
                                  }
                                },
                                labelStyle: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: a.spec == s ? Colors.white : ink,
                                ),
                                selectedColor: pine,
                                backgroundColor: Colors.white,
                                side: BorderSide(color: a.spec == s ? pine : line),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                visualDensity: VisualDensity.compact,
                              );
                            }),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: line),
                          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_outline, size: 12, color: pine),
                            const SizedBox(width: 4),
                            Text(
                              '${filteredDocs.length} ${filteredDocs.length == 1 ? 'doctor' : 'doctors'} nearby',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ink),
                            ),
                          ],
                        ),
                      ),
                      if (a.spec != 'All') ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => a.set(() => a.spec = 'All'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: warnC,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text('Show all ✕', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ink)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 3. Floating Controls
          Positioned(
            right: 14,
            bottom: _selectedDoc != null ? 230 : 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _mapFab(
                  icon: Icons.zoom_out_map_rounded,
                  tooltip: 'Fit all doctors',
                  onTap: _recenterToAllDocs,
                ),
                const SizedBox(height: 8),
                _mapFab(
                  icon: Icons.add,
                  tooltip: 'Zoom in',
                  onTap: () {
                    final cur = _mapController.camera.zoom;
                    _mapController.move(_mapController.camera.center, (cur + 1).clamp(4.0, 18.0));
                  },
                ),
                const SizedBox(height: 8),
                _mapFab(
                  icon: Icons.remove,
                  tooltip: 'Zoom out',
                  onTap: () {
                    final cur = _mapController.camera.zoom;
                    _mapController.move(_mapController.camera.center, (cur - 1).clamp(4.0, 18.0));
                  },
                ),
                const SizedBox(height: 8),
                _mapFab(
                  icon: Icons.my_location_rounded,
                  color: const Color(0xFF2A6BFF),
                  iconColor: Colors.white,
                  tooltip: 'Center on my location',
                  onTap: () {
                    _moveTo(a.userLocation, 15.0);
                  },
                ),
              ],
            ),
          ),

          // 4. Selected Doctor Bottom Card
          if (_selectedDoc != null)
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: _DoctorMapCard(
                doc: _selectedDoc!,
                onClose: () => setState(() => _selectedDoc = null),
                onBook: () {
                  final d = _selectedDoc!;
                  a.set(() {
                    a.doc = a.docs.indexOf(d);
                    a.slot = null;
                  });
                },
              ),
            ),
        ],
      ),
    );
  },
);
}

  Widget _mapFab({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color color = Colors.white,
    Color iconColor = ink,
  }) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      elevation: 3,
      shadowColor: Colors.black38,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, size: 20, color: iconColor),
          ),
        ),
      ),
    );
  }
}

class _PinTrianglePainter extends CustomPainter {
  final Color color;
  const _PinTrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PinTrianglePainter oldDelegate) => oldDelegate.color != color;
}

class _DoctorMapCard extends StatelessWidget {
  final Doc doc;
  final VoidCallback onClose;
  final VoidCallback onBook;

  const _DoctorMapCard({
    required this.doc,
    required this.onClose,
    required this.onBook,
  });

  @override
  Widget build(BuildContext context) {
    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onBook,
            borderRadius: BorderRadius.circular(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                avatar(doc.initials),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              doc.name,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.verified, size: 15, color: pine),
                        ],
                      ),
                      mt('${doc.spec} · ${doc.fac}'),
                      const SizedBox(height: 2),
                      Text(
                        doc.address,
                        style: const TextStyle(fontSize: 11, color: mute),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20, color: mute),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: mint, borderRadius: BorderRadius.circular(12)),
                child: Text('★ ${doc.rating}', style: const TextStyle(color: pine, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFFE8F1FF), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.near_me_rounded, size: 12, color: Color(0xFF2A6BFF)),
                    const SizedBox(width: 3),
                    Text('${doc.dist} km', style: const TextStyle(color: Color(0xFF2A6BFF), fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: bgc, borderRadius: BorderRadius.circular(12)),
                child: Text('₹${doc.fee}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: ink)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: warnC, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  '${doc.free} slots left today',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF7A5A00), fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    final query = Uri.encodeComponent('${doc.lat},${doc.lng} (${doc.fac})');
                    openExternalUrl('https://www.google.com/maps/search/?api=1&query=$query');
                  },
                  icon: const Icon(Icons.directions_rounded, size: 16),
                  label: const Text('Directions', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: pine,
                    side: const BorderSide(color: pine),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: bgc,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    final tel = doc.phone.replaceAll(' ', '');
                    openExternalUrl('tel:$tel');
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    child: const Icon(Icons.phone_rounded, size: 18, color: ink),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onBook,
                  icon: const Icon(Icons.calendar_month_rounded, size: 16),
                  label: const Text('Book', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: coral,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class Profile extends StatelessWidget {
  const Profile({super.key});
  @override
  Widget build(BuildContext c) {
    final a = app;
    final x = a.docs[a.doc!];
    return Column(children: [
      Head(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        backBtn(() => a.set(() => a.doc = null)),
        Row(children: [
          avatar(x.initials), const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(x.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)), Text('${x.spec} · ★ ${x.rating}', style: const TextStyle(color: Colors.white70))]),
        ]),
      ])),
      Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(x.fac, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          mt('${x.dist} km away · Open 9:00–19:00 · Fee ₹${x.fee}'),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.location_on_outlined, size: 14, color: mute),
            const SizedBox(width: 4),
            Expanded(child: Text(x.address, style: const TextStyle(fontSize: 12, color: mute), maxLines: 1, overflow: TextOverflow.ellipsis)),
            TextButton.icon(
              onPressed: () {
                final query = Uri.encodeComponent('${x.lat},${x.lng} (${x.fac})');
                openExternalUrl('https://www.google.com/maps/search/?api=1&query=$query');
              },
              icon: const Icon(Icons.directions, size: 16, color: pine),
              label: const Text('Directions', style: TextStyle(color: pine, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ]),
        ])),
        note(Text(a.why(x)), bg: mint, top: 0),
        h3('Pick a time · today'),
        GridView.count(
          crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 2.4,
          children: [
            for (var i = 0; i < x.slots.length; i++)
              Builder(builder: (c) {
                final gone = x.taken.contains(i), on = a.slot == i;
                return Opacity(opacity: gone ? .35 : 1, child: GestureDetector(
                  onTap: gone ? null : () => a.set(() => a.slot = i),
                  child: Container(alignment: Alignment.center, decoration: BoxDecoration(color: on ? coral : Colors.white, border: Border.all(color: on ? coral : line), borderRadius: BorderRadius.circular(10)),
                      child: Text(x.slots[i], style: TextStyle(fontSize: 13, color: on ? Colors.white : ink, decoration: gone ? TextDecoration.lineThrough : null)))));
              }),
          ],
        ),
        gap(16),
        Btn('Book appointment', () {
          if (a.slot == null) { say(c, 'Pick a time first'); return; }
          say(c, 'Booked. Reminder set.');
          a.set(() { a.appts.insert(0, Appt(a.doc!, 'Today, ${x.slots[a.slot!]}', 'confirmed')); x.taken.add(a.slot!); a.doc = null; a.tab = 'visits'; });
        }, opacity: a.slot == null ? .5 : 1),
        h3('Reviews'),
        CardBox(child: mt('“Short wait, clear explanation.” — demo review')),
        Center(child: mt('Demo provider data · not verified')),
      ])),
    ]);
  }
}

class Visits extends StatelessWidget {
  const Visits({super.key});
  @override
  Widget build(BuildContext c) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16 + MediaQuery.of(c).padding.top, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          title('My visits'), gap(12),
          for (final q in app.appts)
            CardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(app.docs[q.doc].name, style: const TextStyle(fontWeight: FontWeight.w700)), Pill(q.st, k: q.st == 'cancelled' ? 'r' : '')]),
              mt('${q.time} · ${app.docs[q.doc].fac}'),
              if (q.st == 'confirmed') Padding(padding: const EdgeInsets.only(top: 10), child: Row(children: [
                Btn('Reschedule', () => say(c, 'Choose a new slot (demo)'), kind: 1, small: true), const SizedBox(width: 10),
                Btn('Cancel', () { say(c, 'Appointment cancelled'); app.set(() => q.st = 'cancelled'); }, kind: 2, small: true),
              ])),
            ])),
        ]),
      );
}

class Records extends StatelessWidget {
  const Records({super.key});
  @override
  Widget build(BuildContext c) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16 + MediaQuery.of(c).padding.top, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          title('My records'), gap(12),
          for (final r in const [['Blood test report', '12 Oct 2026'], ['Prescription – Dr. Mehta', '03 Sep 2026'], ['ECG summary', '18 Jun 2026']])
            CardBox(child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(r[0], style: const TextStyle(fontWeight: FontWeight.w700)), mt(r[1])]), const Pill('Private')])),
          Btn('Rate a past visit', () => say(c, 'Review form opens (demo)'), kind: 1),
          gap(10),
          mt('Only you and staff you authorise can see these files.'),
          gap(10),
          Btn('Sign out', () => app.go(Scr.welcome), kind: 2),
        ]),
      );
}

// ───────────────────────── Admin portal ─────────────────────────
class Act { final String t; final VoidCallback f; final int k; Act(this.t, this.f, this.k); }

class Admin extends StatelessWidget {
  const Admin({super.key});

  Widget head(String t) => Head(admin: true, top: 20, bottom: 20, Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('CityCare Hospital · Admin', style: TextStyle(fontSize: 12, color: Colors.white70)),
          Text(t, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        ]),
        GestureDetector(onTap: () => app.go(Scr.welcome), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(border: Border.all(color: Colors.white38), borderRadius: BorderRadius.circular(99)), child: const Text('Sign out', style: TextStyle(fontSize: 13)))),
      ]));

  Widget stat(String n, String l) => Expanded(child: Container(
      margin: const EdgeInsets.only(bottom: 10, right: 5, left: 5), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: line), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(n, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)), mt(l)])));

  Widget actions(List<Act> b) => Padding(padding: const EdgeInsets.only(top: 10), child: Row(children: [
        for (final x in b) Padding(padding: const EdgeInsets.only(right: 10), child: Btn(x.t, x.f, small: true, kind: x.k)),
      ]));

  Widget wrap(List<Widget> k) => Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: k));

  @override
  Widget build(BuildContext c) {
    final a = app;
    switch (a.tab) {
      case 'prov':
        return Column(children: [head('Doctors'), wrap([
          Align(alignment: Alignment.centerLeft, child: Btn('+ Add doctor', () => say(c, 'Add-doctor form opens (demo)'), small: true)), gap(10),
          for (final d in a.admDocs)
            CardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(d.name, style: const TextStyle(fontWeight: FontWeight.w700)), Pill(d.on ? 'active' : 'hidden', k: d.on ? '' : 'r')]),
              mt('${d.v ? 'Verified' : 'Not verified'} · fee, hours, services editable'),
              actions([Act('Verify', () => a.set(() => d.v = true), 1), Act(d.on ? 'Hide' : 'Show', () => a.set(() => d.on = !d.on), 2)]),
            ])),
        ])]);
      case 'bk':
        return Column(children: [head('Bookings'), wrap([
          for (final q in a.reqs)
            CardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(q.p, style: const TextStyle(fontWeight: FontWeight.w700)), Pill(q.st, k: q.st == 'requested' ? 'y' : q.st == 'rejected' ? 'r' : '')]),
              mt('${q.d} · ${q.t}'),
              if (q.st == 'requested') actions([Act('Confirm', () => a.set(() => q.st = 'confirmed'), 0), Act('Reject', () => a.set(() => q.st = 'rejected'), 2)]),
            ])),
        ])]);
      case 'rv':
        return Column(children: [head('Reviews'), wrap([
          for (final q in a.revs)
            CardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(q.p, style: const TextStyle(fontWeight: FontWeight.w700)), Pill(q.st, k: q.st == 'removed' ? 'r' : '')]),
              Text(q.t),
              if (q.st == 'pending') actions([Act('Approve', () => a.set(() => q.st = 'approved'), 1), Act('Remove', () => a.set(() => q.st = 'removed'), 2)]),
            ])),
        ])]);
      default:
        return Column(children: [head('Today'), wrap([
          Row(children: [stat('${a.reqs.where((r) => r.st == 'requested').length}', 'Awaiting confirmation'), stat('${a.appts.length + 12}', 'Bookings this week')]),
          Row(children: [stat('${a.admDocs.where((d) => d.on).length}', 'Active doctors'), stat('${a.revs.where((r) => r.st == 'pending').length}', 'Reviews to moderate')]),
          h3('Quick actions'),
          Wrap(spacing: 10, runSpacing: 8, children: [
            Btn('Add doctor', () => a.set(() => a.tab = 'prov'), kind: 1, small: true),
            Btn('Publish slots', () => say(c, 'Slot publisher opens (demo)'), kind: 1, small: true),
            Btn('Audit log', () => say(c, 'Audit log opens (demo)'), kind: 1, small: true),
          ]),
          h3('Recent activity'),
          CardBox(child: mt('Dr. Kapoor’s profile verified · 10:12\nSlot 16:00 published for Dr. Sharma · 09:40')),
        ])]);
    }
  }
}
