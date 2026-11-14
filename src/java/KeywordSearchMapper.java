package com.eduvos.itbda4.mapreduce;

import java.io.IOException;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.apache.hadoop.io.LongWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Mapper;
import org.apache.hadoop.mapreduce.lib.input.FileSplit;

/**
 * Hadoop MapReduce Mapper for dynamic, case-insensitive keyword search.
 * Tracks row (1-based line number) via an internal counter incremented per record
 * and column position (both character offset and 1-based word token index).
 */
public class KeywordSearchMapper extends Mapper<LongWritable, Text, Text, Text> {

    private String targetKeyword;
    private Pattern keywordPattern;
    private long currentRowNumber = 0L;
    private String currentFileName = "unknown";

    private final Text outKey = new Text();
    private final Text outVal = new Text();

    @Override
    protected void setup(Context context) throws IOException, InterruptedException {
        targetKeyword = context.getConfiguration().get("search.keyword", "");
        if (targetKeyword == null || targetKeyword.trim().isEmpty()) {
            throw new IllegalArgumentException("Dynamic property 'search.keyword' must be supplied.");
        }
        keywordPattern = Pattern.compile(Pattern.quote(targetKeyword.trim()), Pattern.CASE_INSENSITIVE);
        if (context.getInputSplit() instanceof FileSplit) {
            currentFileName = ((FileSplit) context.getInputSplit()).getPath().getName();
        }
        currentRowNumber = 0L;
    }

    @Override
    protected void map(LongWritable key, Text value, Context context)
            throws IOException, InterruptedException {
        currentRowNumber++;
        String line = value.toString();
        Matcher matcher = keywordPattern.matcher(line);

        while (matcher.find()) {
            int charCol = matcher.start() + 1; // 1-based character column
            String prefix = line.substring(0, matcher.start()).trim();
            int wordCol = prefix.isEmpty() ? 1 : prefix.split("\\s+").length + 1;
            String matchedToken = line.substring(matcher.start(), matcher.end());

            outKey.set(currentFileName);
            outVal.set(String.format("Row=%d, CharCol=%d, WordCol=%d (match='%s')",
                    currentRowNumber, charCol, wordCol, matchedToken));
            context.write(outKey, outVal);
        }
    }
}
