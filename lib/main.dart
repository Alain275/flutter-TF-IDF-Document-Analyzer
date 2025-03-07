// Import necessary Flutter and Dart packages
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io' show File;
import 'dart:math';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Main entry point of the application
void main() {
  // Run the app starting with TFIDFApp as the root widget                                
  runApp(const TFIDFApp());
}

/// The root application widget
/// This is a stateless widget that sets up the app theme and initial route
class TFIDFApp extends StatelessWidget {
  // Constructor with key parameter for widget identification
  const TFIDFApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // MaterialApp is the root widget that provides material design elements
    return MaterialApp(
      title: 'TF-IDF Document Analyzer', // App title shown in task switchers
      // Light theme configuration
      theme: ThemeData(
        primarySwatch: Colors.blue,      // Primary color palette
        brightness: Brightness.light,    // Light mode
        useMaterial3: true,              // Use Material 3 design
      ),
      home: const DocumentAnalyzerScreen(), // Initial screen/route
    );
  }
}

/// The main screen of the application
/// This is a stateful widget that handles document analysis
class DocumentAnalyzerScreen extends StatefulWidget {
  // Constructor with key parameter
  const DocumentAnalyzerScreen({Key? key}) : super(key: key);

  @override
  // Create and return the state associated with this widget
  State<DocumentAnalyzerScreen> createState() => _DocumentAnalyzerScreenState();
}

/// The state associated with DocumentAnalyzerScreen
/// Contains the business logic and UI building for the main screen
class _DocumentAnalyzerScreenState extends State<DocumentAnalyzerScreen> {
  // State variables
  final List<Document> _documents = [];           // List to store loaded documents
  final TextEditingController _searchController = TextEditingController(); // Controller for search input
  String _searchTerm = '';                        // Current search term
  bool _isLoading = false;                        // Loading state flag
  bool _hasResults = false;                       // Flag to show if search has results
  String _errorMessage = '';                      // Error message to display

  @override
  void dispose() {
    // Clean up the controller when the widget is removed from the tree
    _searchController.dispose();
    super.dispose(); // Call parent dispose method
  }

  /// Method to handle document picking based on platform
  Future<void> _pickDocuments() async {
    try {
      // Set loading state and clear any previous errors
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      // Use different approach based on whether we're on web or native platform
      if (kIsWeb) {
        // Web-specific document picking
        await _pickWebDocuments();
      } else {
        // Native platforms document picking (Android, iOS, desktop)
        await _pickNativeDocuments();
      }
      
      // Only compute TF-IDF if we have documents
      if (_documents.isNotEmpty) {
        // Calculate TF-IDF values for all documents
        _computeTFIDFForAllDocuments();
      }
      
    } catch (e) {
      // Handle errors by displaying them in the UI
      setState(() {
        _errorMessage = 'Error: $e';
      });
      // Show a snackbar with the error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading documents: $e')),
      );
    } finally {
      // End loading state regardless of success or failure
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Specialized method for picking documents on web platform
  Future<void> _pickWebDocuments() async {
    // Open file picker dialog with web-specific options
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,                 // Only allow specific file types
      allowedExtensions: ['txt', 'pdf','docs'], // Allowed file extensions
      allowMultiple: true,                  // Allow multiple file selection
      withData: true,                       // Important: request bytes data for web
    );

    // Process files if any were selected
    if (result != null && result.files.isNotEmpty) {
      // Store initial document count for generating unique IDs
      int initialDocCount = _documents.length;
      
      // Process each file
      for (var i = 0; i < result.files.length; i++) {
        var file = result.files[i];
        
        // Skip files that don't have byte data
        if (file.bytes == null || file.bytes!.isEmpty) {
          continue;
        }

        try {
          // Convert the byte array to a string using UTF-8 encoding
          String content = utf8.decode(file.bytes!);
          // Generate a unique ID for this file
          String uniqueId = 'web-file-${initialDocCount + i + 1}';
          
          // Add the document to our collection
          _documents.add(Document(
            name: file.name,                   // Original filename
            path: uniqueId,                    // Generated unique ID as path
            content: content,                  // File content as string
            wordCount: _countWords(content),   // Count words in the document
          ));
        } catch (e) {
          // Log any errors processing individual files but continue with others
          print('Error processing file ${file.name}: $e');
        }
      }
    }
  }

  /// Specialized method for picking documents on native platforms
  Future<void> _pickNativeDocuments() async {
    // Open file picker dialog with native-specific options
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,                 // Only allow specific file types
      allowedExtensions: ['txt', 'pdf','docs'], // Allowed file extensions
      allowMultiple: true,                  // Allow multiple file selection
    );

    // Process files if any were selected
    if (result != null) {
      for (var file in result.files) {
        // Only process files with valid paths
        if (file.path != null) {
          // Read the file content as a string
          String content = await File(file.path!).readAsString();
          
          // Add the document to our collection
          _documents.add(Document(
            name: file.name,                   // Original filename
            path: file.path!,                  // Full file path
            content: content,                  // File content as string
            wordCount: _countWords(content),   // Count words in the document
          ));
        }
      }
    }
  }

  /// Count the number of words in a text string
  int _countWords(String text) {
    // Split by whitespace and filter out empty strings
    return text.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;
  }

  /// Calculate TF-IDF values for all terms in all documents
  void _computeTFIDFForAllDocuments() {
    // Safety check - don't proceed if there are no documents
    if (_documents.isEmpty) return;
    
    // First, gather all unique terms across all documents
    Set<String> allTerms = {};
    for (var doc in _documents) {
      // Extract words from each document
      List<String> words = doc.content.toLowerCase()  // Convert to lowercase
          .replaceAll(RegExp(r'[^\w\s]'), '')        // Remove non-word characters
          .split(RegExp(r'\s+'))                     // Split by whitespace
          .where((word) => word.isNotEmpty)          // Remove empty strings
          .toList();
          
      // Add all words to the set of terms (duplicates are automatically removed)
      allTerms.addAll(words);
    }
    
    // Calculate document frequency for each term
    // (The number of documents that contain the term)
    Map<String, int> documentFrequency = {};
    for (String term in allTerms) {
      int count = 0;
      for (var doc in _documents) {
        // Check if this document contains the term
        if (doc.content.toLowerCase().contains(term)) {
          count++;
        }
      }
      documentFrequency[term] = count;
    }
    
    // Calculate TF-IDF for each term in each document
    for (var doc in _documents) {
      // Map to store TF-IDF values for each term in this document
      Map<String, double> tfIdfValues = {};
      
      // Count term frequency in this document
      // (How many times each term appears in this document)
      Map<String, int> termFrequency = {};
      List<String> words = doc.content.toLowerCase()
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .toList();
      
      // Count occurrences of each word
      for (var word in words) {
        termFrequency[word] = (termFrequency[word] ?? 0) + 1;
      }
      
      // Calculate TF-IDF for each term
      for (var term in termFrequency.keys) {
        // Term frequency (TF): occurrences of term / total terms in document
        double tf = termFrequency[term]! / words.length;
        
        // Inverse document frequency (IDF): log(total docs / docs containing term)
        double idf = log(_documents.length / max(1, documentFrequency[term] ?? 1).toDouble());

        
        // TF-IDF is the product of TF and IDF
        tfIdfValues[term] = tf * idf;
      }
      
      // Store the calculated values in the document
      doc.tfIdfValues = tfIdfValues;
    }
  }

  /// Handle search button press or enter key in search field
  void _performSearch() {
    // Get the search term from the text field and clean it
    String term = _searchController.text.trim().toLowerCase();
    // Don't search for empty terms
    if (term.isEmpty) return;
    
    // Update state to show search results
    setState(() {
      _searchTerm = term;
      _hasResults = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Scaffold provides the basic material design visual layout structure
    return Scaffold(
      // App bar at the top of the screen
      appBar: AppBar(
        title: const Text('TF-IDF Document Analyzer'),
        // Action buttons in the app bar
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline), // Info icon
            onPressed: _showInfoDialog,           // Show information dialog
          ),
        ],
      ),
      // Main body of the app
      body: _isLoading
          // Show loading indicator while loading
          ? const Center(child: CircularProgressIndicator())
          // Show main UI when not loading
          : Column(
              children: [
                // Search bar and document load button
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      // Search text field
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            labelText: 'Enter a word to analyze',
                            border: OutlineInputBorder(),
                            // Search button inside the text field
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.search),
                              onPressed: _performSearch,
                            ),
                          ),
                          // Handle Enter key press
                          onSubmitted: (_) => _performSearch(),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Document load button
                      ElevatedButton.icon(
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Load Documents'),
                        onPressed: _pickDocuments,
                      ),
                    ],
                  ),
                ),
                // Error message display (only shown when there is an error)
                if (_errorMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      _errorMessage,
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                // Main content area
                Expanded(
                  child: _documents.isEmpty
                      // Show placeholder message when no documents are loaded
                      ? const Center(
                          child: Text('No documents loaded. Please upload some documents to begin.'),
                        )
                      // Show main content when documents are loaded
                      : _buildMainContent(),
                ),
              ],
            ),
    );
  }

  /// Build the main content area with document list and analysis results
  Widget _buildMainContent() {
    // Use a Row to create a sidebar layout
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Document list (left sidebar)
        SizedBox(
          width: 250,
          child: Card(
            margin: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sidebar header
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Documents (${_documents.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const Divider(), // Horizontal divider line
                // List of documents
                Expanded(
                  child: ListView.builder(
                    itemCount: _documents.length,
                    itemBuilder: (context, index) {
                      final doc = _documents[index];
                      return ListTile(
                        title: Text(
                          doc.name,
                          overflow: TextOverflow.ellipsis, // Handle long titles
                        ),
                        subtitle: Text('${doc.wordCount} words'),
                        onTap: () => _showDocumentDetails(doc), // Show details on tap
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        
        // Main content area (right side)
        Expanded(
          child: !_hasResults
              // Show prompt when no search has been performed yet
              ? const Center(
                  child: Text('Enter a term to see TF-IDF analysis across documents.'),
                )
              // Show search results when available
              : _buildTfIdfResults(),
        ),
      ],
    );
  }

  /// Build the TF-IDF analysis results for the searched term
  Widget _buildTfIdfResults() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search term header
          Text(
            'TF-IDF Analysis for "$_searchTerm"',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 24),
          // Section title
          Text(
            'Document Comparison',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          // Bar chart visualization
          Expanded(
            child: _buildSimpleBarChart(),
          ),
          const SizedBox(height: 16),
          // Data table with detailed values
          _buildTfIdfTable(),
        ],
      ),
    );
  }

  /// Build a simple bar chart to visualize TF-IDF scores
  Widget _buildSimpleBarChart() {
    // Get maximum TF-IDF value for normalization
    double maxTfIdf = 0.0;
    for (var doc in _documents) {
      double value = doc.tfIdfValues[_searchTerm] ?? 0;
      if (value > maxTfIdf) maxTfIdf = value;
    }

    // If no values found, show a message
    if (maxTfIdf == 0) {
      return Center(child: Text('No data available for term "$_searchTerm"'));
    }

    // Build the chart
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Chart title
        const Text('TF-IDF Score by Document', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        // Scrollable list of bars
        Expanded(
          child: ListView.builder(
            itemCount: _documents.length,
            itemBuilder: (context, index) {
              final doc = _documents[index];
              final tfIdfValue = doc.tfIdfValues[_searchTerm] ?? 0;
              // Calculate percentage of width based on max value (for visual scaling)
              double percentage = maxTfIdf > 0 ? tfIdfValue / maxTfIdf : 0;
              
              // Ensure percentage is valid (between 0 and 1) for widthFactor
              double validPercentage = max(0.0, min(1.0, percentage));
              
              // Select color based on index (cycling through available colors)
              final colors = [
                Colors.blue,
                Colors.red,
                Colors.green,
                Colors.orange,
                Colors.purple,
                Colors.teal,
                Colors.pink,
                Colors.amber,
              ];
              final color = colors[index % colors.length];
              
              // Create a bar with label for each document
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Document name
                    Text(
                      doc.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Bar with value
                    Row(
                      children: [
                        // Bar container
                        Expanded(
                          child: Container(
                            height: 24,
                            child: Stack(
                              children: [
                                // Background (empty bar)
                                Container(
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                // Colored bar (only shown if there's a value)
                                if (validPercentage > 0)
                                  FractionallySizedBox(
                                    widthFactor: validPercentage,
                                    child: Container(
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: color,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Numeric value display
                        SizedBox(
                          width: 70,
                          child: Text(
                            tfIdfValue.toStringAsFixed(4), // Format to 4 decimal places
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Build a data table with detailed TF-IDF values
  Widget _buildTfIdfTable() {
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal, // Allow horizontal scrolling for wide tables
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Document')),
            DataColumn(label: Text('Term Frequency')),
            DataColumn(label: Text('TF-IDF Score')),
          ],
          rows: _documents.map((doc) {
            // Calculate term frequency for the search term in this document
            List<String> words = doc.content.toLowerCase()
                .replaceAll(RegExp(r'[^\w\s]'), '')
                .split(RegExp(r'\s+'))
                .where((word) => word.isNotEmpty)
                .toList();
            
            // Count occurrences of the searched term
            int termCount = words.where((word) => word == _searchTerm).length;
            // Calculate frequency (occurrences / total words)
            double termFrequency = words.isEmpty ? 0 : termCount / words.length;
            // Get the TF-IDF value
            double tfIdfValue = doc.tfIdfValues[_searchTerm] ?? 0;
            
            // Create a table row for this document
            return DataRow(
              cells: [
                DataCell(Text(doc.name)), // Document name
                DataCell(Text('${(termFrequency * 100).toStringAsFixed(2)}%')), // Term frequency as percentage
                DataCell(Text(tfIdfValue.toStringAsFixed(4))), // TF-IDF value
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  /// Show a dialog with detailed document information
  void _showDocumentDetails(Document document) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(document.name), // Document name as dialog title
        content: SizedBox(
          width: double.maxFinite, // Full width
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Word count
              Text('Word Count: ${document.wordCount}'),
              const SizedBox(height: 16),
              // Top terms section
              const Text('Top TF-IDF Terms:'),
              const SizedBox(height: 8),
              _buildTopTermsList(document), // List of top terms by TF-IDF
              const SizedBox(height: 16),
              // Document preview section
              const Text('Preview:'),
              const SizedBox(height: 8),
              // Scrollable document preview with truncation for long documents
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    document.content.substring(
                      0,
                      min(500, document.content.length), // Show first 500 chars
                    ) + (document.content.length > 500 ? '...' : ''),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Close button
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Build a list of the top TF-IDF terms for a document
  Widget _buildTopTermsList(Document document) {
    // Get all terms sorted by TF-IDF value (highest first)
    List<MapEntry<String, double>> sortedTerms = document.tfIdfValues.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    // Take just the top 10 terms
    List<MapEntry<String, double>> topTerms = sortedTerms.take(10).toList();
    
    // Create a scrollable list of terms with their TF-IDF values
    return SizedBox(
      height: 200,
      child: ListView.builder(
        itemCount: topTerms.length,
        itemBuilder: (context, index) {
          return ListTile(
            dense: true,
            title: Text(topTerms[index].key), // Term
            trailing: Text(topTerms[index].value.toStringAsFixed(4)), // TF-IDF value
          );
        },
      ),
    );
  }

  /// Show a dialog with information about TF-IDF
  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About TF-IDF'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              // General explanation of TF-IDF
              Text(
                'TF-IDF (Term Frequency-Inverse Document Frequency) is a numerical statistic that reflects how important a word is to a document in a collection.',
              ),
              SizedBox(height: 16),
              // Term Frequency explanation
              Text(
                'Term Frequency (TF): How frequently a term appears in a document. It is calculated as the number of times a term appears in a document divided by the total number of terms in the document.',
              ),
              SizedBox(height: 8),
              // Inverse Document Frequency explanation
              Text(
                'Inverse Document Frequency (IDF): Measures how important a term is. It is calculated as the logarithm of the number of documents divided by the number of documents containing the term.',
              ),
              SizedBox(height: 8),
              // TF-IDF explanation
              Text(
                'TF-IDF = TF × IDF: This gives a high value for terms that appear frequently in a specific document but rarely across all documents.',
              ),
            ],
          ),
        ),
        // Close button
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

/// Class to represent a document with its content and analysis
class Document {
  final String name;               // Document name
  final String path;               // File path or unique ID
  final String content;            // Document text content
  final int wordCount;             // Number of words in the document
  Map<String, double> tfIdfValues = {}; // TF-IDF values for each term

  // Constructor
  Document({
    required this.name,
    required this.path,
    required this.content,
    required this.wordCount,
  });
}