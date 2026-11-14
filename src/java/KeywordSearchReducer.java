package com.eduvos.itbda4.mapreduce;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Reducer;

/**
 * Hadoop MapReduce Reducer collecting all (Row, Column) coordinates per document
 * and emitting the sorted coordinate list alongside total occurrence count.
 */
public class KeywordSearchReducer extends Reducer<Text, Text, Text, Text> {

    private final Text summaryValue = new Text();

    @Override
    protected void reduce(Text key, Iterable<Text> values, Context context)
            throws IOException, InterruptedException {
        List<String> locations = new ArrayList<>();
        for (Text val : values) {
            locations.add(val.toString());
        }
        String joined = String.join(" | ", locations);
        summaryValue.set(String.format("TotalMatches=%d -> [%s]", locations.size(), joined));
        context.write(key, summaryValue);
    }
}
