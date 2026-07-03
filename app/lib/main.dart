import 'package:flutter/material.dart';
import 'package:todori/src/rust/api.dart';
import 'package:todori/src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(MyApp(greeting: greet(name: 'Todori')));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.greeting});

  final Future<String>? greeting;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Todori',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: MyHomePage(
        title: 'Todori',
        greeting: greeting ?? greet(name: 'Todori'),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title, required this.greeting});

  final String title;
  final Future<String> greeting;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FutureBuilder<String>(
              future: widget.greeting,
              builder: (context, snapshot) {
                return Text(snapshot.data ?? 'Loading Rust bridge...');
              },
            ),
            const SizedBox(height: 24),
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
