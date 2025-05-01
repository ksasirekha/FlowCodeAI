import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const FigmaToCodeApp());
}

class FigmaToCodeApp extends StatelessWidget {
  const FigmaToCodeApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Figma to HTML/CSS/JS',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const FigmaToCodeScreen(),
    );
  } 
}

class FigmaToCodeScreen extends StatefulWidget {
  const FigmaToCodeScreen({Key? key}) : super(key: key);

  @override
  _FigmaToCodeScreenState createState() => _FigmaToCodeScreenState();
}

class _FigmaToCodeScreenState extends State<FigmaToCodeScreen> with SingleTickerProviderStateMixin {
  // Figma API credentials
  final String _defaultApiToken = "figd_iqh3Yo15QT0gpQXVOiU1-nPLR2mcesnZSauyst0a";
  final String _defaultFileId = "VHXBxEJiWrRRqbR5uyDrZe";
  
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _fileIdController = TextEditingController();
  
  bool _isLoading = false;
  String _error = '';
  List<dynamic> _components = [];
  Map<String, String> _idToNameMap = {};
  
  late TabController _tabController;
  String _htmlCode = '';
  String _cssCode = '';
  String _jsCode = '';
  
  @override
  void initState() {
    super.initState();
    _tokenController.text = _defaultApiToken;
    _fileIdController.text = _defaultFileId;
    _tabController = TabController(length: 3, vsync: this);
  }
  
  @override
  void dispose() {
    _tokenController.dispose();
    _fileIdController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // Convert RGBA to HEX
  String? rgbaToHex(Map<String, dynamic>? color) {
    if (color == null) return null;
    
    int r = (color['r'] * 255).toInt();
    int g = (color['g'] * 255).toInt();
    int b = (color['b'] * 255).toInt();
    int a = (color['a'] * 255).toInt();
    
    return a < 255 
        ? '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}${a.toRadixString(16).padLeft(2, '0')}'
        : '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';
  }

  // Extract metadata from a node
  Map<String, dynamic> extractMetadata(Map<String, dynamic> node) {
    var metadata = {
      'ID': node['id'],
      'Name': node['name'] ?? 'Unnamed (${node['id']})',
      'Type': node['type'],
      'Position': node['absoluteBoundingBox'] ?? {},
      'Size': {
        'width': node['absoluteBoundingBox']?['width'] ?? 0,
        'height': node['absoluteBoundingBox']?['height'] ?? 0
      },
      'Fills': node['fills']?.where((fill) => fill['color'] != null)
          .map((fill) => rgbaToHex(fill['color']))
          .toList() ?? [],
      'Strokes': node['strokes']?.where((stroke) => stroke['color'] != null)
          .map((stroke) => rgbaToHex(stroke['color']))
          .toList() ?? [],
      'Effects': node['effects'] ?? [],
      'Opacity': node['opacity'] ?? 1,
      'Rotation': node['rotation'] ?? 0,
      'Constraints': node['constraints'] ?? {},
      'Visible': node['visible'] ?? true,
      'Navigation': []
    };

    // Extract text details if it's a text node
    if (node['type'] == 'TEXT') {
      metadata['Text'] = node['characters'] ?? '';
      metadata['Text Style'] = node['style'] ?? {};
    }

    return metadata;
  }

  // Extract components recursively
  void traverse(Map<String, dynamic> node, List<dynamic> componentsData, 
      {String? parentId, String? pageName}) {
    
    // If the node is a page, update the page_name
    if (node['type'] == 'CANVAS') {
      pageName = node['name'] ?? 'Unknown Page';
    }

    var componentInfo = extractMetadata(node);
    componentInfo['Parent'] = parentId;
    componentInfo['Page'] = pageName;

    String componentId = componentInfo['ID'];
    String componentName = componentInfo['Name'];
    _idToNameMap[componentId] = componentName;

    // Extract navigation (transitionNodeID)
    if (node.containsKey('transitionNodeID')) {
      String destId = node['transitionNodeID'];
      componentInfo['Navigation'].add({
        'Event': 'Click',
        'Source': componentName,
        'Destination': destId,
        'Destination Name': _idToNameMap[destId] ?? 'Unknown ($destId)'
      });
    }

    // Check for buttons or links
    if (node['type'] == 'BUTTON' || node.containsKey('clickAction')) {
      String destId = node['clickAction']?['destination'] ?? 'Unknown';
      componentInfo['Navigation'].add({
        'Event': 'Click',
        'Source': componentName,
        'Destination': destId,
        'Destination Name': _idToNameMap[destId] ?? 'Unknown ($destId)'
      });
    }

    // Store component if it's a UI element
    if (componentInfo['Type'] != 'DOCUMENT' && 
        componentInfo['Type'] != 'CANVAS' &&
        componentInfo['Visible'] == true) {
      componentsData.add(componentInfo);
    }

    // Recursively check child nodes
    if (node.containsKey('children')) {
      for (var child in node['children']) {
        traverse(child, componentsData, parentId: componentId, pageName: pageName);
      }
    }
  }

  // Update navigation data with actual names
  void updateNavigationNames(List<dynamic> componentsData) {
    for (var component in componentsData) {
      for (var nav in component['Navigation']) {
        String destId = nav['Destination'];
        nav['Destination Name'] = _idToNameMap[destId] ?? 'Unknown ($destId)';
      }
    }
  }

  // Generate HTML from components
  String generateHtml(List<dynamic> components) {
    StringBuffer html = StringBuffer();
    
    html.writeln('<!DOCTYPE html>');
    html.writeln('<html lang="en">');
    html.writeln('<head>');
    html.writeln('    <meta charset="UTF-8">');
    html.writeln('    <meta name="viewport" content="width=device-width, initial-scale=1.0">');
    html.writeln('    <title>Figma Design</title>');
    html.writeln('    <link rel="stylesheet" href="styles.css">');
    html.writeln('</head>');
    html.writeln('<body>');
    html.writeln('    <div id="app">');
    
    // Sort components by pages
    Map<String, List<dynamic>> componentsByPage = {};
    for (var component in components) {
      String pageName = component['Page'] ?? 'Unknown';
      if (!componentsByPage.containsKey(pageName)) {
        componentsByPage[pageName] = [];
      }
      componentsByPage[pageName]!.add(component);
    }
    
    // Create a section for each page
    componentsByPage.forEach((pageName, pageComponents) {
      html.writeln('        <section class="page" id="${_sanitizeId(pageName)}">');
      html.writeln('            <h2>${_escapeHtml(pageName)}</h2>');
      
      // Generate elements for each component
      for (var component in pageComponents) {
        String id = _sanitizeId(component['ID']);
        String name = _escapeHtml(component['Name']);
        String type = component['Type'];
        String className = 'component ${type.toLowerCase()}';
        
        if (type == 'FRAME' || type == 'GROUP') {
          html.writeln('            <div id="$id" class="$className">');
          html.writeln('                <!-- $name -->');
          html.writeln('            </div>');
        } else if (type == 'TEXT') {
          html.writeln('            <p id="$id" class="$className">${_escapeHtml(component['Text'] ?? '')}</p>');
        } else if (type == 'RECTANGLE') {
          html.writeln('            <div id="$id" class="$className rectangle"></div>');
        } else if (type == 'ELLIPSE') {
          html.writeln('            <div id="$id" class="$className ellipse"></div>');
        } else if (type == 'BUTTON') {
          html.writeln('            <button id="$id" class="$className">$name</button>');
        } else {
          html.writeln('            <div id="$id" class="$className">$name</div>');
        }
      }
      
      html.writeln('        </section>');
    });
    
    html.writeln('    </div>');
    html.writeln('    <script src="script.js"></script>');
    html.writeln('</body>');
    html.writeln('</html>');
    
    return html.toString();
  }
  
  // Generate CSS from components
  String generateCss(List<dynamic> components) {
    StringBuffer css = StringBuffer();
    
    css.writeln('/* Generated CSS from Figma */');
    css.writeln('* {');
    css.writeln('    margin: 0;');
    css.writeln('    padding: 0;');
    css.writeln('    box-sizing: border-box;');
    css.writeln('}');
    
    css.writeln('');
    css.writeln('body {');
    css.writeln('    font-family: Arial, sans-serif;');
    css.writeln('}');
    
    css.writeln('');
    css.writeln('#app {');
    css.writeln('    position: relative;');
    css.writeln('}');
    
    css.writeln('');
    css.writeln('.page {');
    css.writeln('    padding: 20px;');
    css.writeln('    margin-bottom: 30px;');
    css.writeln('}');
    
    css.writeln('');
    css.writeln('.component {');
    css.writeln('    position: absolute;');
    css.writeln('}');
    
    // Generate style for each component
    for (var component in components) {
      String id = _sanitizeId(component['ID']);
      
      css.writeln('');
      css.writeln('#$id {');
      
      // Position and size
      if (component['Position'] != null && component['Position'].isNotEmpty) {
        css.writeln('    left: ${component['Position']['x']}px;');
        css.writeln('    top: ${component['Position']['y']}px;');
      }
      
      if (component['Size'] != null) {
        if (component['Size']['width'] != null) {
          css.writeln('    width: ${component['Size']['width']}px;');
        }
        if (component['Size']['height'] != null) {
          css.writeln('    height: ${component['Size']['height']}px;');
        }
      }
      
      // Background color (from fills)
      List<dynamic> fills = component['Fills'] ?? [];
      if (fills.isNotEmpty && fills[0] != null) {
        css.writeln('    background-color: ${fills[0]};');
      }
      
      // Border color (from strokes)
      List<dynamic> strokes = component['Strokes'] ?? [];
      if (strokes.isNotEmpty && strokes[0] != null) {
        css.writeln('    border: 1px solid ${strokes[0]};');
      }
      
      // Opacity
      if (component['Opacity'] != null && component['Opacity'] != 1) {
        css.writeln('    opacity: ${component['Opacity']};');
      }
      
      // Rotation
      if (component['Rotation'] != null && component['Rotation'] != 0) {
        css.writeln('    transform: rotate(${component['Rotation']}deg);');
      }
      
      // Text styling
      if (component['Type'] == 'TEXT' && component['Text Style'] != null) {
        var textStyle = component['Text Style'];
        if (textStyle['fontSize'] != null) {
          css.writeln('    font-size: ${textStyle['fontSize']}px;');
        }
        if (textStyle['fontWeight'] != null) {
          css.writeln('    font-weight: ${textStyle['fontWeight']};');
        }
        if (textStyle['fontFamily'] != null) {
          css.writeln('    font-family: "${textStyle['fontFamily']}";');
        }
        if (textStyle['textAlignHorizontal'] != null) {
          css.writeln('    text-align: ${textStyle['textAlignHorizontal'].toLowerCase()};');
        }
      }
      
      css.writeln('}');
    }
    
    // Special styling for shapes
    css.writeln('');
    css.writeln('.ellipse {');
    css.writeln('    border-radius: 50%;');
    css.writeln('}');
    
    return css.toString();
  }
  
  // Generate JavaScript for navigation and interactions
  String generateJs(List<dynamic> components) {
    StringBuffer js = StringBuffer();
    
    js.writeln('// Generated JavaScript from Figma');
    js.writeln('document.addEventListener("DOMContentLoaded", function() {');
    
    // Add click handlers for navigation
    bool hasNavigation = false;
    for (var component in components) {
      List<dynamic> navs = component['Navigation'];
      if (navs.isNotEmpty) {
        hasNavigation = true;
        String id = _sanitizeId(component['ID']);
        
        js.writeln('    // Click handler for ${component['Name']}');
        js.writeln('    document.getElementById("$id").addEventListener("click", function() {');
        
        for (var nav in navs) {
          String destId = _sanitizeId(nav['Destination']);
          js.writeln('        // Navigate to ${nav['Destination Name']}');
          js.writeln('        document.getElementById("$destId").scrollIntoView({ behavior: "smooth" });');
        }
        
        js.writeln('    });');
        js.writeln('');
      }
    }
    
    if (!hasNavigation) {
      js.writeln('    // No navigation links found in the design');
    }
    
    js.writeln('    console.log("Figma design interactions initialized");');
    js.writeln('});');
    
    return js.toString();
  }
  
  // Helper method to sanitize IDs for HTML
  String _sanitizeId(String id) {
    return id.replaceAll(':', '').replaceAll(';', '').replaceAll(' ', '_');
  }
  
  // Helper method to escape HTML special characters
  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#039;');
  }

  // Fetch data from Figma API
  Future<void> fetchFigmaData() async {
    setState(() {
      _isLoading = true;
      _error = '';
      _components = [];
      _idToNameMap = {};
      _htmlCode = '';
      _cssCode = '';
      _jsCode = '';
    });

    final token = _tokenController.text;
    final fileId = _fileIdController.text;
    
    if (token.isEmpty || fileId.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'API Token and File ID are required';
      });
      return;
    }

    try {
      final response = await http.get(
        Uri.parse('https://api.figma.com/v1/files/$fileId'),
        headers: {'X-Figma-Token': token},
      );

      if (response.statusCode == 200) {
        final figmaJson = json.decode(response.body);
        final componentsData = <dynamic>[];

        // Process all pages in the document
        for (var page in figmaJson['document']['children']) {
          traverse(page, componentsData);
        }

        // Update navigation data with actual names
        updateNavigationNames(componentsData);
        
        // Generate code
        final htmlCode = generateHtml(componentsData);
        final cssCode = generateCss(componentsData);
        final jsCode = generateJs(componentsData);

        setState(() {
          _components = componentsData;
          _htmlCode = htmlCode;
          _cssCode = cssCode;
          _jsCode = jsCode;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _error = 'Error ${response.statusCode}: ${response.body}';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Exception: $e';
      });
    }
  }

  // Copy code to clipboard
  void _copyToClipboard(String code) {
    Clipboard.setData(ClipboardData(text: code)).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Code copied to clipboard')),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Figma to HTML/CSS/JS Converter'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // API credentials form
            TextField(
              controller: _tokenController,
              decoration: const InputDecoration(
                labelText: 'Figma API Token',
                hintText: 'Enter your Figma API token',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _fileIdController,
              decoration: const InputDecoration(
                labelText: 'Figma File ID',
                hintText: 'Enter your Figma file ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            
            // Extract button
            ElevatedButton(
              onPressed: _isLoading ? null : fetchFigmaData,
              child: _isLoading
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text('Extracting...'),
                      ],
                    )
                  : const Text('Extract and Generate Code'),
            ),
            
            // Error message
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  _error,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            
            // Code output
            if (_htmlCode.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'Generated ${_components.length} components',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              
              // Tab bar for different code types
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'HTML'),
                  Tab(text: 'CSS'),
                  Tab(text: 'JavaScript'),
                ],
              ),
              
              // Tab content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // HTML tab
                    _buildCodeTab(_htmlCode, 'HTML'),
                    
                    // CSS tab
                    _buildCodeTab(_cssCode, 'CSS'),
                    
                    // JavaScript tab
                    _buildCodeTab(_jsCode, 'JavaScript'),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCodeTab(String code, String type) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$type Code', style: const TextStyle(fontWeight: FontWeight.bold)),
              ElevatedButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
                onPressed: () => _copyToClipboard(code),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(4),
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: SelectableText(
                  code,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}