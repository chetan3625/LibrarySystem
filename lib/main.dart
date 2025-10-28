// Library Admin Panel - PVG College Nashik
// Save this as lib/main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'dart:math' as math;

// -----------------------------
// DATA MODELS (Book, Borrower, Loan)
// -----------------------------

class Book {
  final int? id;
  final String title;
  final String author;
  final String isbn;
  final int totalCopies;
  final int availableCopies;

  Book({this.id, required this.title, required this.author, required this.isbn, required this.totalCopies, required this.availableCopies});

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'author': author,
    'isbn': isbn,
    'totalCopies': totalCopies,
    'availableCopies': availableCopies,
  };

  factory Book.fromMap(Map<String, dynamic> m) => Book(
    id: m['id'] as int?,
    title: m['title'] as String,
    author: m['author'] as String,
    isbn: m['isbn'] as String,
    totalCopies: m['totalCopies'] as int,
    availableCopies: m['availableCopies'] as int,
  );
}

class Borrower {
  final int? id;
  final String name;
  final String phone;

  Borrower({this.id, required this.name, required this.phone});

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'phone': phone};

  factory Borrower.fromMap(Map<String, dynamic> m) => Borrower(
    id: m['id'] as int?,
    name: m['name'] as String,
    phone: m['phone'] as String,
  );
}

class Loan {
  final int? id;
  final int bookId;
  final int borrowerId;
  final DateTime issueDate;
  final DateTime? returnDate;
  final double fineAmount;

  Loan({this.id, required this.bookId, required this.borrowerId, required this.issueDate, this.returnDate, this.fineAmount = 0.0});

  Map<String, dynamic> toMap() => {
    'id': id,
    'bookId': bookId,
    'borrowerId': borrowerId,
    'issueDate': issueDate.toIso8601String(),
    'returnDate': returnDate?.toIso8601String(),
    'fineAmount': fineAmount,
  };

  factory Loan.fromMap(Map<String, dynamic> m) => Loan(
    id: m['id'] as int?,
    bookId: m['bookId'] as int,
    borrowerId: m['borrowerId'] as int,
    issueDate: DateTime.parse(m['issueDate'] as String),
    returnDate: m['returnDate'] != null ? DateTime.parse(m['returnDate'] as String) : null,
    fineAmount: (m['fineAmount'] as num).toDouble(),
  );
}

// -----------------------------
// DATABASE HELPER (sqflite)
// -----------------------------

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  DatabaseHelper._internal();

  static Database? _db;
  static const _name = 'library_pvg_nashik.db';
  static const _version = 1;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final databasesPath = await getDatabasesPath();
    final dbPath = path.join(databasesPath, _name);
    _db = await openDatabase(dbPath, version: _version, onCreate: _onCreate);
    return _db!;
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE books(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        author TEXT NOT NULL,
        isbn TEXT NOT NULL,
        totalCopies INTEGER NOT NULL,
        availableCopies INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE borrowers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE loans(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bookId INTEGER NOT NULL,
        borrowerId INTEGER NOT NULL,
        issueDate TEXT NOT NULL,
        returnDate TEXT,
        fineAmount REAL NOT NULL
      )
    ''');
  }

  // Database operations (insertBook, getBooks, deleteBook, insertBorrower, getBorrowers, getLoans, updateBookAvailableCopies, returnLoan, borrowBook)
  // ... (unchanged from the original structure, focusing on clean SQL logic)

  // Books
  Future<int> insertBook(Book b) async {
    final db = await database;
    return await db.insert('books', b.toMap());
  }

  Future<List<Book>> getBooks() async {
    final db = await database;
    final rows = await db.query('books', orderBy: 'title');
    return rows.map((r) => Book.fromMap(r)).toList();
  }

  Future<int> deleteBook(int id) async {
    final db = await database;
    return db.delete('books', where: 'id = ?', whereArgs: [id]);
  }

  // Borrowers
  Future<int> insertBorrower(Borrower b) async {
    final db = await database;
    return await db.insert('borrowers', b.toMap());
  }

  Future<List<Borrower>> getBorrowers() async {
    final db = await database;
    final rows = await db.query('borrowers', orderBy: 'name');
    return rows.map((r) => Borrower.fromMap(r)).toList();
  }

  // Loans
  Future<List<Loan>> getLoans() async {
    final db = await database;
    final rows = await db.query('loans', orderBy: 'issueDate DESC');
    return rows.map((r) => Loan.fromMap(r)).toList();
  }

  Future<int> updateBookAvailableCopies(Database db, int bookId, int delta) async {
    final bookRows = await db.query('books', where: 'id=?', whereArgs: [bookId]);
    if (bookRows.isEmpty) throw Exception('Book not found for update');
    final available = bookRows.first['availableCopies'] as int?;

    if (available == null) throw Exception('Available copies data missing or invalid');

    return db.update('books', {'availableCopies': available + delta}, where: 'id=?', whereArgs: [bookId]);
  }

  Future<double> returnLoan(int loanId, int bookId, double fine) async {
    final db = await database;
    await db.update('loans', {'returnDate': DateTime.now().toIso8601String(), 'fineAmount': fine}, where: 'id = ?', whereArgs: [loanId]);

    await updateBookAvailableCopies(db, bookId, 1);

    return fine;
  }

  Future<void> borrowBook(int bookId, int borrowerId) async {
    final db = await database;
    await db.transaction((txn) async {
      final bookRows = await txn.query('books', where: 'id=?', whereArgs: [bookId]);
      if (bookRows.isEmpty) throw Exception('Book not found');
      final available = bookRows.first['availableCopies'] as int?;

      if (available == null || available <= 0) throw Exception('No copies available');

      await txn.update('books', {'availableCopies': available - 1}, where: 'id=?', whereArgs: [bookId]);
      await txn.insert('loans', Loan(bookId: bookId, borrowerId: borrowerId, issueDate: DateTime.now()).toMap());
    });
  }
}

// -----------------------------
// STATE: AUTHENTICATION MODEL
// -----------------------------

class AuthModel extends ChangeNotifier {
  String? _loggedInAdminName;
  bool get isAuthenticated => _loggedInAdminName != null;
  String get adminName => _loggedInAdminName ?? 'Guest User';
  String get adminEmail => _loggedInAdminName != null ? 'rushikesh@pvg.ac.in' : 'guest@pvg.ac.in'; // Static for demo email

  // Hardcoded credentials
  static const String correctUsername = 'RK';
  static const String correctPassword = '3421';

  Future<bool> login(String username, String password) async {
    // Simulate API call delay
    await Future.delayed(const Duration(milliseconds: 500));
    if (username == correctUsername && password == correctPassword) {
      _loggedInAdminName = 'Rushikesh Bankar'; // Dynamic name based on successful login
      notifyListeners();
      return true;
    }
    return false;
  }

  void logout() {
    _loggedInAdminName = null;
    notifyListeners();
  }
}

// -----------------------------
// STATE: LIBRARY DATA MODEL
// -----------------------------

class LibraryModel extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;
  List<Book> books = [];
  List<Borrower> borrowers = [];
  List<Loan> loans = [];
  bool loading = false;

  static const int loanLimitDays = 7;
  static const double finePerDay = 5.0;

  LibraryModel() {
    // Do not load on creation, let AuthModel trigger load after login
  }

  Future<void> loadAll() async {
    loading = true;
    notifyListeners();
    try {
      books = await _db.getBooks();
      borrowers = await _db.getBorrowers();
      loans = await _db.getLoans();
    } catch (e) {
      debugPrint('Error loading data: $e');
    }
    loading = false;
    notifyListeners();
  }

  Future<void> addBook(String title, String author, String isbn, int copies) async {
    final book = Book(title: title, author: author, isbn: isbn, totalCopies: copies, availableCopies: copies);
    await _db.insertBook(book);
    await loadAll();
  }

  Future<void> addBorrower(String name, String phone) async {
    final b = Borrower(name: name, phone: phone);
    await _db.insertBorrower(b);
    await loadAll();
  }

  Future<void> borrowBook(int bookId, int borrowerId) async {
    await _db.borrowBook(bookId, borrowerId);
    await loadAll();
  }

  double calculateFine(DateTime issueDate, DateTime? returnDate) {
    final now = returnDate ?? DateTime.now();
    final days = now.difference(issueDate).inDays;
    final overdue = days - loanLimitDays;
    return overdue > 0 ? overdue * finePerDay : 0.0;
  }

  Future<double> returnBook(int loanId, int bookId) async {
    final loan = loans.firstWhere((l) => l.id == loanId, orElse: () => throw Exception('Loan not found'));
    final fine = calculateFine(loan.issueDate, DateTime.now());
    await _db.returnLoan(loanId, bookId, fine);
    await loadAll();
    return fine;
  }

  Future<void> deleteBook(int bookId) async {
    await DatabaseHelper.instance.deleteBook(bookId);
    await loadAll();
  }

  List<Loan> get activeLoans => loans.where((l) => l.returnDate == null).toList();

  double get totalFinesAccrued {
    double sum = 0;
    for (var l in loans) {
      if (l.returnDate != null) {
        sum += l.fineAmount;
      } else {
        sum += calculateFine(l.issueDate, null);
      }
    }
    return sum;
  }
}

// -----------------------------
// UI: MAIN APP STRUCTURE
// -----------------------------

void mainWrapper() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthModel()),
        // LibraryModel only loads data when authenticated
        ChangeNotifierProxyProvider<AuthModel, LibraryModel>(
          create: (_) => LibraryModel(),
          update: (_, auth, library) {
            // Only trigger loadAll when authentication state changes to true
            if (auth.isAuthenticated && library!.books.isEmpty && !library.loading) {
              library.loadAll();
            }
            return library!;
          },
        ),
      ],
      child: const AppRoot(),
    ),
  );
}

// Main entry point
void main() => mainWrapper();

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PVG College Library Admin',
      theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF673AB7), primary: const Color(0xFF673AB7), secondary: const Color(0xFF9C27B0)), // Deep Purple theme
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFF7F8FA),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF673AB7), // Deep Purple
            foregroundColor: Colors.white,
            elevation: 4,
            centerTitle: true,
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
          ),
          textTheme: const TextTheme(
            headlineMedium: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w700),
            titleLarge: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w600),
          )
      ),
      // Conditional rendering based on authentication state
      home: Consumer<AuthModel>(
        builder: (context, auth, _) {
          if (auth.isAuthenticated) {
            return const DashboardScreen();
          } else {
            return const LoginPage();
          }
        },
      ),
    );
  }
}

// -----------------------------
// UI: LOGIN PAGE
// -----------------------------

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Login - PVG College Nashik')),
      body: Center(
        child: SingleChildScrollView( // Prevents overflow on small screens/keyboard open
          padding: const EdgeInsets.all(32.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_person, size: 60, color: Theme.of(context).primaryColor),
                    const SizedBox(height: 20),
                    Text('Librarian Sign In', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(labelText: 'Username (rushikesh)', prefixIcon: Icon(Icons.person)),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      decoration: const InputDecoration(labelText: 'Password (3421)', prefixIcon: Icon(Icons.lock)),
                      obscureText: true,
                    ),
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500)),
                      ),
                    const SizedBox(height: 30),
                    _isLoading
                        ? const CircularProgressIndicator()
                        : SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _login,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 4
                        ),
                        child: const Text('Login', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final success = await Provider.of<AuthModel>(context, listen: false).login(
      _usernameController.text,
      _passwordController.text,
    );

    if (!success) {
      setState(() {
        _errorMessage = 'Invalid credentials. Please try again.';
        _isLoading = false;
      });
    } else {
      // Login successful, AuthModel state change will trigger AppRoot to show Dashboard
    }
  }
}

// -----------------------------
// UI: DASHBOARD SCREEN
// -----------------------------

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  static void _showAbout(BuildContext context) {
    showAboutDialog(
        context: context,
        applicationName: 'PVG College Library Admin Panel',
        applicationVersion: '1.0',
        applicationLegalese: '© 2024 Rushikesh Bankar', // Dynamic placeholder for developer name
        children: [
          const Text('A robust and responsive library management system developed for PVG College Nashik.'),
        ]
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isPortrait = mediaQuery.orientation == Orientation.portrait;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard for PVG College Nashik'),
        actions: [
          IconButton(onPressed: () => _showAbout(context), icon: const Icon(Icons.info_outline)),
        ],
      ),
      drawer: const AppDrawer(),
      body: SafeArea(
        child: Consumer2<AuthModel, LibraryModel>(builder: (context, auth, model, child) {
          if (model.loading) return const Center(child: CircularProgressIndicator());

          final bookCount = model.books.length;
          final borrowerCount = model.borrowers.length;
          final activeLoans = model.activeLoans.length;
          final totalFines = model.totalFinesAccrued;

          return SingleChildScrollView( // Use SingleChildScrollView to prevent general body overflow
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Welcome, ${auth.adminName}', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: Theme.of(context).primaryColor)),
                const SizedBox(height: 8),
                Text('Overview of your collection and active transactions.', style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 20),

                // Responsive Stats Grid (Overflow Fix)
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: isPortrait ? 2 : 4, // 2 columns in portrait, 4 in landscape
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  // Adjusted aspect ratio to prevent content overflow within the card
                  childAspectRatio: isPortrait ? 1.4 : 1.8,
                  children: [
                    _StatCard(title: 'Total Books', value: bookCount.toString(), icon: Icons.menu_book, color: Colors.blue.shade700),
                    _StatCard(title: 'Active Members', value: borrowerCount.toString(), icon: Icons.people_alt, color: Colors.green.shade700),
                    _StatCard(title: 'Active Loans', value: activeLoans.toString(), icon: Icons.swap_horiz, color: Colors.orange.shade700),
                    _StatCard(title: 'Total Fines', value: '₹${totalFines.toStringAsFixed(0)}', icon: Icons.attach_money, color: Colors.red.shade700),
                  ],
                ),
                const SizedBox(height: 25),

                // Quick actions - Horizontal scrollable
                Text('Quick Actions', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _QuickActionButton(label: 'Add Book', icon: Icons.library_add, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddBookPageWidget()))),
                    const SizedBox(width: 12),
                    _QuickActionButton(label: 'Add Member', icon: Icons.person_add, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddMemberPage()))),
                    const SizedBox(width: 12),
                    _QuickActionButton(label: 'Issue Book', icon: Icons.bookmark_add, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IssueBookPage()))),
                    const SizedBox(width: 12),
                    _QuickActionButton(label: 'Return Book', icon: Icons.bookmark_remove, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReturnBookPage()))),
                  ]),
                ),
                const SizedBox(height: 25),

                // Recent activity (loans)
                Text('Recent Loans', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // Confine the list height to prevent overflow
                      SizedBox(
                        height: math.min(mediaQuery.size.height * 0.4, model.loans.length * 70.0), // Max 40% of screen height
                        child: model.loans.isEmpty
                            ? const Center(child: Text('No loan activity yet.', style: TextStyle(color: Colors.grey)))
                            : ListView.separated(
                          physics: const ClampingScrollPhysics(),
                          separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                          itemCount: math.min(5, model.loans.length),
                          itemBuilder: (context, index) {
                            final loan = model.loans[index];
                            final book = model.books.firstWhere((b) => b.id == loan.bookId, orElse: () => Book(id: null, title: 'Deleted Book', author: '-', isbn: '-', totalCopies: 0, availableCopies: 0));
                            final borrower = model.borrowers.firstWhere((b) => b.id == loan.borrowerId, orElse: () => Borrower(id: null, name: 'Deleted Member', phone: '-'));
                            final dueDate = loan.issueDate.add(const Duration(days: LibraryModel.loanLimitDays));
                            final overdue = loan.returnDate == null && dueDate.isBefore(DateTime.now());

                            return ListTile(
                              leading: Icon(Icons.book, color: overdue ? Colors.redAccent : Theme.of(context).primaryColor),
                              title: Text(book.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text('${borrower.name} • Due ${_formatDate(dueDate)}'),
                              trailing: overdue
                                  ? Icon(Icons.error, color: Colors.red.shade600, size: 20)
                                  : (loan.returnDate != null ? Icon(Icons.check_circle_outline, color: Colors.green.shade600, size: 20) : null),
                            );
                          },
                        ),
                      )
                    ]),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

String _formatDate(DateTime d) {
  return '${d.day}/${d.month}/${d.year}';
}

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthModel>(
      builder: (context, auth, child) {
        return Drawer(
          child: SafeArea(
            child: Column(
              children: [
                UserAccountsDrawerHeader(
                  decoration: BoxDecoration(color: Theme.of(context).primaryColor),
                  accountName: Text(auth.adminName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  accountEmail: Text(auth.adminEmail), // Dynamic email
                  currentAccountPicture: CircleAvatar(backgroundColor: Colors.white, child: Text(auth.adminName.isNotEmpty ? auth.adminName[0].toUpperCase() : 'A', style: TextStyle(fontSize: 24, color: Theme.of(context).primaryColor))),
                ),
                _DrawerItem(icon: Icons.dashboard, title: 'Dashboard', onTap: () => Navigator.pop(context)),
                _DrawerItem(icon: Icons.menu_book, title: 'Books', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BooksPage()))),
                _DrawerItem(icon: Icons.people, title: 'Members', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MembersPage()))),
                _DrawerItem(icon: Icons.receipt_long, title: 'Fines Report', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FineReportPage()))),
                const Divider(),
                _DrawerItem(
                    icon: Icons.info_outline,
                    title: 'About PVG Admin',
                    onTap: () {
                      Navigator.pop(context);
                      DashboardScreen._showAbout(context);
                    }
                ),
                const Spacer(),
                _DrawerItem(icon: Icons.logout, title: 'Sign Out', onTap: () {
                  auth.logout();
                  Navigator.pop(context); // Close drawer
                  // AppRoot will handle navigation to LoginPage
                }, color: Colors.red),
              ],
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------
// Small UI components (Responsive/Overflow proof)
// -----------------------------

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard({required this.title, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 6,
      child: Container(
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.3), width: 1.5)
        ),
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 30),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w500, color: color, fontSize: 14), overflow: TextOverflow.ellipsis)),
              ],
            ),
            // Explicitly constrain font size to prevent overflow in constrained grid item
            Text(
                value,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 28, // Fixed size for consistency
                    color: Colors.black87
                )
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? color;
  const _DrawerItem({required this.icon, required this.title, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color ?? Theme.of(context).primaryColor),
      title: Text(title, style: TextStyle(color: color ?? Colors.black87)),
      onTap: onTap,
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _QuickActionButton({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white),
        label: Text(label, style: const TextStyle(color: Colors.white)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.secondary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 4,
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
      ),
    );
  }
}

// -----------------------------
// Pages: Books, Members, Fine report, Return (All forms use ListView for responsiveness)
// -----------------------------

class BooksPage extends StatelessWidget {
  const BooksPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Books Collection')),
      body: Consumer<LibraryModel>(builder: (context, model, child) {
        if (model.loading) return const Center(child: CircularProgressIndicator());
        if (model.books.isEmpty) return const Center(child: Text('No books in the library. Add one!'));
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: model.books.length,
          itemBuilder: (context, i) {
            final b = model.books[i];
            return Card(
              elevation: 3,
              margin: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                leading: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(color: Theme.of(context).primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.book_outlined, color: Theme.of(context).primaryColor)
                ),
                title: Text(b.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('Author: ${b.author} • ISBN: ${b.isbn}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('${b.availableCopies}/${b.totalCopies}', style: TextStyle(fontWeight: FontWeight.bold, color: b.availableCopies > 0 ? Colors.green : Colors.red)),
                      Text('Avail.', style: Theme.of(context).textTheme.bodySmall),
                    ]),
                    IconButton(
                        icon: const Icon(Icons.delete_forever, color: Colors.redAccent, size: 24),
                        onPressed: () async {
                          if (b.id != null) {
                            await model.deleteBook(b.id!);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Book deleted successfully')));
                          }
                        }
                    )
                  ],
                ),
              ),
            );
          },
        );
      }),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddBookPageWidget())),
        child: const Icon(Icons.add),
        backgroundColor: Theme.of(context).colorScheme.secondary,
        foregroundColor: Colors.white,
      ),
    );
  }
}

class AddBookPageWidget extends StatefulWidget {
  const AddBookPageWidget({super.key});

  @override
  State<AddBookPageWidget> createState() => _AddBookPageState();
}

class _AddBookPageState extends State<AddBookPageWidget> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _author = TextEditingController();
  final _isbn = TextEditingController();
  final _copies = TextEditingController(text: '1');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add New Book')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          // ListView ensures keyboard won't cause bottom overflow
          child: ListView(children: [
            TextFormField(controller: _title, decoration: const InputDecoration(labelText: 'Book Title', prefixIcon: Icon(Icons.book_outlined)), validator: (v) => (v == null || v.isEmpty) ? 'Required' : null),
            const SizedBox(height: 16),
            TextFormField(controller: _author, decoration: const InputDecoration(labelText: 'Author Name', prefixIcon: Icon(Icons.person_outline)), validator: (v) => (v == null || v.isEmpty) ? 'Required' : null),
            const SizedBox(height: 16),
            TextFormField(controller: _isbn, decoration: const InputDecoration(labelText: 'ISBN (Optional)', prefixIcon: Icon(Icons.qr_code))),
            const SizedBox(height: 16),
            TextFormField(controller: _copies, decoration: const InputDecoration(labelText: 'Total Copies', prefixIcon: Icon(Icons.numbers)), keyboardType: TextInputType.number, validator: (v) => (v == null || int.tryParse(v) == null || int.parse(v) <= 0) ? 'Must be a positive number' : null),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: () async {
                if (_formKey.currentState!.validate()) {
                  try {
                    await Provider.of<LibraryModel>(context, listen: false).addBook(_title.text, _author.text, _isbn.text, int.parse(_copies.text));
                    _title.clear(); _author.clear(); _isbn.clear(); _copies.text = '1';
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Book added successfully!')));
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error adding book: $e')));
                  }
                }
              },
              icon: const Icon(Icons.save),
              label: const Text('Save Book'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            )
          ]),
        ),
      ),
    );
  }
}

class AddMemberPage extends StatefulWidget {
  const AddMemberPage({super.key});

  @override
  State<AddMemberPage> createState() => _AddMemberPageState();
}

class _AddMemberPageState extends State<AddMemberPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add New Member')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: ListView(children: [ // ListView for responsiveness
            TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Member Name', prefixIcon: Icon(Icons.badge_outlined)), validator: (v) => (v == null || v.isEmpty) ? 'Required' : null),
            const SizedBox(height: 16),
            TextFormField(controller: _phone, decoration: const InputDecoration(labelText: 'Phone Number', prefixIcon: Icon(Icons.phone_android)), keyboardType: TextInputType.phone, validator: (v) => (v == null || v.isEmpty) ? 'Required' : null),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: () async {
                if (_formKey.currentState!.validate()) {
                  try {
                    await Provider.of<LibraryModel>(context, listen: false).addBorrower(_name.text, _phone.text);
                    _name.clear(); _phone.clear();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Member added successfully!')));
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error adding member: $e')));
                  }
                }
              },
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Register Member'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            )
          ]),
        ),
      ),
    );
  }
}

class MembersPage extends StatelessWidget {
  const MembersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Library Members')),
      body: Consumer<LibraryModel>(builder: (context, model, child) {
        if (model.loading) return const Center(child: CircularProgressIndicator());
        if (model.borrowers.isEmpty) return const Center(child: Text('No members registered.'));
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: model.borrowers.length,
          itemBuilder: (context, i) {
            final m = model.borrowers[i];
            return Card(
                elevation: 3,
                margin: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: CircleAvatar(backgroundColor: Colors.orange.shade100, child: Text(m.name.isNotEmpty ? m.name[0].toUpperCase() : '?', style: TextStyle(color: Colors.orange.shade800))),
                  title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Phone: ${m.phone}'),
                  trailing: const Icon(Icons.chevron_right),
                )
            );
          },
        );
      }),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddMemberPage())),
        child: const Icon(Icons.person_add),
        backgroundColor: Theme.of(context).colorScheme.secondary,
        foregroundColor: Colors.white,
      ),
    );
  }
}

class FineReportPage extends StatelessWidget {
  const FineReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fines & Overdue Report')),
      body: Consumer<LibraryModel>(builder: (context, model, child) {
        if (model.loading) return const Center(child: CircularProgressIndicator());

        final finedLoans = model.loans.where((l) => l.fineAmount > 0 || (l.returnDate == null && model.calculateFine(l.issueDate, null) > 0)).toList();

        if (finedLoans.isEmpty) return const Center(child: Text('All good! No fines or overdue books.'));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('Total Fines Due: ₹${model.totalFinesAccrued.toStringAsFixed(2)}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.red.shade700)),
            ),
            Expanded( // Expanded is safe here because parent Column is in a Scaffold body
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: finedLoans.length,
                itemBuilder: (context, index) {
                  final loan = finedLoans[index];
                  final book = model.books.firstWhere((b) => b.id == loan.bookId, orElse: () => Book(id: null, title: 'Deleted Book', author: '-', isbn: '-', totalCopies: 0, availableCopies: 0));
                  final borrower = model.borrowers.firstWhere((b) => b.id == loan.borrowerId, orElse: () => Borrower(id: null, name: 'Deleted Member', phone: '-'));
                  final isReturned = loan.returnDate != null;
                  final fine = isReturned ? loan.fineAmount : model.calculateFine(loan.issueDate, null);

                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isReturned ? Colors.grey.shade300 : Colors.red.shade200)),
                    child: ListTile(
                      leading: Icon(Icons.receipt_long, color: isReturned ? Colors.grey : Colors.red),
                      title: Text(borrower.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        "${book.title} (${isReturned ? 'Returned' : 'OVERDUE'})",
                        style: TextStyle(color: isReturned ? Colors.grey : Colors.red.shade700),
                      ),
                      trailing: Text(
                        "₹${fine.toStringAsFixed(2)}",
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent, fontSize: 16),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
      ),
    );
  }
}

class IssueBookPage extends StatefulWidget {
  const IssueBookPage({super.key});

  @override
  State<IssueBookPage> createState() => _IssueBookPageState();
}

class _IssueBookPageState extends State<IssueBookPage> {
  int? _bookId;
  int? _borrowerId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Issue Book')),
      body: Consumer<LibraryModel>(builder: (context, model, child) {
        if (model.loading) return const Center(child: CircularProgressIndicator());
        final availableBooks = model.books.where((b) => b.availableCopies > 0).toList();

        if (availableBooks.isEmpty || model.borrowers.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(
                availableBooks.isEmpty ? 'No books are currently available for loan.' : 'No members registered yet.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: ListView(children: [ // ListView for responsiveness
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(labelText: 'Select Member', prefixIcon: Icon(Icons.person_outline)),
              items: model.borrowers.map((br) => DropdownMenuItem(value: br.id, child: Text(br.name))).toList(),
              value: _borrowerId,
              hint: const Text('Select Member'),
              onChanged: (v) => setState(() => _borrowerId = v),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(labelText: 'Select Book', prefixIcon: Icon(Icons.book_online)),
              items: availableBooks.map((b) => DropdownMenuItem(value: b.id, child: Text('${b.title} (${b.availableCopies} available)'))).toList(),
              value: _bookId,
              hint: const Text('Select Book'),
              onChanged: (v) => setState(() => _bookId = v),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: (_bookId == null || _borrowerId == null) ? null : () async {
                try {
                  await Provider.of<LibraryModel>(context, listen: false).borrowBook(_bookId!, _borrowerId!);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Book successfully issued!')));
                  Navigator.pop(context);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Issue failed: ${e.toString()}')));
                }
              },
              icon: const Icon(Icons.send),
              label: const Text('Confirm Issue'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            )
          ]),
        );
      }),
    );
  }
}

class ReturnBookPage extends StatefulWidget {
  const ReturnBookPage({super.key});

  @override
  State<ReturnBookPage> createState() => _ReturnBookPageState();
}

class _ReturnBookPageState extends State<ReturnBookPage> {
  int? _loanId;
  Loan? _selectedLoan;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Return Book')),
      body: Consumer<LibraryModel>(builder: (context, model, child) {
        if (model.loading) return const Center(child: CircularProgressIndicator());

        final activeLoans = model.activeLoans;

        if (activeLoans.isEmpty) {
          return const Center(child: Text('No books are currently out on loan.', style: TextStyle(fontSize: 16, color: Colors.grey)));
        }

        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: ListView(
            children: [
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'Select Active Loan', prefixIcon: Icon(Icons.assignment_turned_in)),
                items: activeLoans.map((loan) {
                  final book = model.books.firstWhere((b) => b.id == loan.bookId, orElse: () => Book(id: 0, title: 'Unknown Book', author: '', isbn: '', totalCopies: 0, availableCopies: 0));
                  final borrower = model.borrowers.firstWhere((br) => br.id == loan.borrowerId, orElse: () => Borrower(id: 0, name: 'Unknown Member', phone: ''));
                  return DropdownMenuItem(
                      value: loan.id,
                      child: Text('${book.title} (by ${borrower.name})')
                  );
                }).toList(),
                value: _loanId,
                hint: const Text('Choose Loan to Return'),
                onChanged: (v) {
                  setState(() {
                    _loanId = v;
                    _selectedLoan = activeLoans.firstWhere((l) => l.id == v);
                  });
                },
              ),
              const SizedBox(height: 20),

              if (_selectedLoan != null) ...[
                _FineDisplay(
                    loan: _selectedLoan!,
                    model: model,
                    bookTitle: model.books.firstWhere((b) => b.id == _selectedLoan!.bookId, orElse: () => Book(id: 0, title: 'Unknown Book', author: '', isbn: '', totalCopies: 0, availableCopies: 0)).title
                ),
                const SizedBox(height: 30),
              ],

              ElevatedButton.icon(
                onPressed: (_loanId == null || _selectedLoan == null) ? null : () async {
                  try {
                    final fine = await Provider.of<LibraryModel>(context, listen: false).returnBook(_selectedLoan!.id!, _selectedLoan!.bookId);

                    String message = 'Book returned successfully!';
                    if (fine > 0) {
                      message += ' Fine charged: ₹${fine.toStringAsFixed(2)}';
                    }
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
                    Navigator.pop(context);
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Return failed: ${e.toString()}')));
                  }
                },
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Confirm Return'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              )
            ],
          ),
        );
      }),
    );
  }
}

class _FineDisplay extends StatelessWidget {
  final Loan loan;
  final LibraryModel model;
  final String bookTitle;
  const _FineDisplay({required this.loan, required this.model, required this.bookTitle});

  @override
  Widget build(BuildContext context) {
    final fine = model.calculateFine(loan.issueDate, null);
    final dueDate = loan.issueDate.add(const Duration(days: LibraryModel.loanLimitDays));
    final overdue = fine > 0;

    return Card(
      elevation: 4,
      color: overdue ? Colors.red.shade50 : Colors.green.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: overdue ? Colors.red.shade300 : Colors.green.shade300)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Book: $bookTitle', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const Divider(),
            _InfoRow(label: 'Issue Date', value: _formatDate(loan.issueDate)),
            _InfoRow(label: 'Due Date', value: _formatDate(dueDate), valueColor: overdue ? Colors.red.shade700 : Colors.green.shade700),
            const SizedBox(height: 10),
            if (overdue)
              _InfoRow(
                  label: 'Overdue Fine',
                  value: '₹${fine.toStringAsFixed(2)}',
                  valueColor: Colors.red.shade700,
                  icon: Icons.warning_amber_rounded
              )
            else
              _InfoRow(
                  label: 'Status',
                  value: 'No Fine Due',
                  valueColor: Colors.green.shade700,
                  icon: Icons.check_circle
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final IconData? icon;
  const _InfoRow({required this.label, required this.value, this.valueColor, this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (icon != null) Icon(icon, size: 18, color: valueColor ?? Colors.black54),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black54)),
            ],
          ),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: valueColor ?? Colors.black87)),
        ],
      ),
    );
  }
}
