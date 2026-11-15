package com.eduvos.itbda4.mapreduce;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Reducer;

/**
 * Hadoop MapReduce Reducer collecting all (Row, Column) coordinates per document
 * and emitting the sorted coordinate list alongside total occurrence count.
 */
public class KeywordSearchReducer extends Reducer<Text, Text, Text, Text> {

    private static final Pattern LOCATION = Pattern.compile("Row=(\\d+), CharCol=(\\d+)");

    private final Text summaryValue = new Text();

    @Override
    protected void reduce(Text key, Iterable<Text> values, Context context)
            throws IOException, InterruptedException {
        List<String> locations = new ArrayList<>();
        for (Text val : values) {
            locations.add(val.toString());
        }
        locations.sort((a, b) -> {
            Matcher ma = LOCATION.matcher(a);
            Matcher mb = LOCATION.matcher(b);
            if (!ma.find() || !mb.find()) return a.compareTo(b);
            int byRow = Long.compare(Long.parseLong(ma.group(1)), Long.parseLong(mb.group(1)));
            return byRow != 0 ? byRow : Integer.compare(Integer.parseInt(ma.group(2)), Integer.parseInt(mb.group(2)));
        });
        String joined = String.join(" | ", locations);
        summaryValue.set(String.format("TotalMatches=%d -> [%s]", locations.size(), joined));
        context.write(key, summaryValue);
    }
}
