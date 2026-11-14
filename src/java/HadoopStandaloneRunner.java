import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.regex.*;

/**
 * Pure JDK 21 Standalone MapReduce Execution Harness for Keyword Search.
 * Mirrors the exact InputSplit -> Map -> Shuffle/Sort -> Reduce -> Output lifecycle
 * on map_reduce_test_docs without requiring external Hadoop daemon jars on Windows.
 */
public class HadoopStandaloneRunner {

    static class KeyValue {
        final String key;
        final String value;
        KeyValue(String key, String value) {
            this.key = key;
            this.value = value;
        }
    }

    // Mapper Phase: processes each <RowNumber, LineText> split dynamically
    public static List<KeyValue> mapSplit(Path docPath, String keyword) throws IOException {
        List<KeyValue> emitted = new ArrayList<>();
        Pattern pattern = Pattern.compile(Pattern.quote(keyword.trim()), Pattern.CASE_INSENSITIVE);
        String fileName = docPath.getFileName().toString();

        List<String> lines = Files.readAllLines(docPath, StandardCharsets.UTF_8);
        for (int row = 1; row <= lines.size(); row++) {
            String line = lines.get(row - 1);
            Matcher m = pattern.matcher(line);
            while (m.find()) {
                int charCol = m.start() + 1;
                String before = line.substring(0, m.start());
                int wordCol = before.trim().isEmpty() ? 1 : before.trim().split("\\s+").length + 1;
                // Extract full word surrounding match for reporting clarity
                int wStart = m.start();
                while (wStart > 0 && !Character.isWhitespace(line.charAt(wStart - 1))) wStart--;
                int wEnd = m.end();
                while (wEnd < line.length() && !Character.isWhitespace(line.charAt(wEnd))) wEnd++;
                String fullToken = line.substring(wStart, wEnd).replaceAll("[\\p{Punct}\\u2018\\u2019\\u201C\\u201D]+$", "");
                boolean exactWord = fullToken.equalsIgnoreCase(keyword.trim());

                String val = String.format("Row=%d, CharCol=%d, WordCol=%d, Token='%s', ExactWord=%s",
                        row, charCol, wordCol, fullToken, exactWord);
                emitted.add(new KeyValue(fileName, val));
            }
        }
        return emitted;
    }

    // Shuffle & Sort Phase: groups intermediate <DocName, Location> pairs by key
    public static Map<String, List<String>> shuffleAndSort(List<KeyValue> intermediate, List<String> allDocs) {
        Map<String, List<String>> grouped = new TreeMap<>();
        for (String doc : allDocs) {
            grouped.put(doc, new ArrayList<>());
        }
        for (KeyValue kv : intermediate) {
            grouped.computeIfAbsent(kv.key, k -> new ArrayList<>()).add(kv.value);
        }
        return grouped;
    }

    // Reducer Phase: aggregates matches per document and produces final output
    public static void reduceAndEmit(Map<String, List<String>> grouped, Path outputFile, String keyword) throws IOException {
        StringBuilder sb = new StringBuilder();
        sb.append(String.format("MapReduce Dynamic Keyword Search Output | Keyword='%s' (Case-Insensitive)%n", keyword));
        sb.append("====================================================================================\n");
        int grandTotal = 0;
        for (Map.Entry<String, List<String>> entry : grouped.entrySet()) {
            List<String> locs = entry.getValue();
            grandTotal += locs.size();
            sb.append(String.format("%s\tTotalMatches=%d%n", entry.getKey(), locs.size()));
            for (String loc : locs) {
                sb.append(String.format("    -> %s%n", loc));
            }
        }
        sb.append("====================================================================================\n");
        sb.append(String.format("Grand Total Occurrences Across Corpus: %d%n", grandTotal));
        Files.writeString(outputFile, sb.toString(), StandardCharsets.UTF_8);
        System.out.print(sb.toString());
    }

    public static void main(String[] args) throws Exception {
        if (args.length < 3) {
            System.err.println("Usage: java HadoopStandaloneRunner <input_dir> <output_file> <keyword>");
            System.exit(1);
        }
        Path inputDir = Paths.get(args[0]);
        Path outputFile = Paths.get(args[1]);
        String keyword = args[2];

        List<Path> docs = new ArrayList<>();
        try (DirectoryStream<Path> ds = Files.newDirectoryStream(inputDir, "*.txt")) {
            for (Path p : ds) docs.add(p);
        }
        docs.sort(Comparator.comparing(p -> p.getFileName().toString()));
        List<String> docNames = new ArrayList<>();
        List<KeyValue> mapOutputs = new ArrayList<>();

        for (Path doc : docs) {
            docNames.add(doc.getFileName().toString());
            mapOutputs.addAll(mapSplit(doc, keyword));
        }
        Map<String, List<String>> shuffled = shuffleAndSort(mapOutputs, docNames);
        reduceAndEmit(shuffled, outputFile, keyword);
    }
}
