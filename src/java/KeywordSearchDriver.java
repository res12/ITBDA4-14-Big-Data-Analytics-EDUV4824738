package com.eduvos.itbda4.mapreduce;

import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Job;
import org.apache.hadoop.mapreduce.lib.input.FileInputFormat;
import org.apache.hadoop.mapreduce.lib.input.TextInputFormat;
import org.apache.hadoop.mapreduce.lib.output.FileOutputFormat;
import org.apache.hadoop.mapreduce.lib.output.TextOutputFormat;

/**
 * Hadoop MapReduce Driver configuring the job dynamically from CLI arguments:
 * args[0] = input corpus path, args[1] = output path, args[2] = dynamic search keyword.
 */
public class KeywordSearchDriver {

    public static void main(String[] args) throws Exception {
        if (args.length < 3) {
            System.err.println("Usage: KeywordSearchDriver <input_dir> <output_dir> <keyword>");
            System.exit(1);
        }

        Configuration conf = new Configuration();
        conf.set("search.keyword", args[2]);
        conf.setBoolean("mapreduce.map.speculative", false);
        conf.setBoolean("mapreduce.output.fileoutputformat.compress", false);

        Job job = Job.getInstance(conf, "Dynamic Case-Insensitive Keyword Search: " + args[2]);
        job.setJarByClass(KeywordSearchDriver.class);

        job.setInputFormatClass(TextInputFormat.class);
        job.setOutputFormatClass(TextOutputFormat.class);

        job.setMapperClass(KeywordSearchMapper.class);
        job.setReducerClass(KeywordSearchReducer.class);
        job.setNumReduceTasks(1);

        job.setMapOutputKeyClass(Text.class);
        job.setMapOutputValueClass(Text.class);
        job.setOutputKeyClass(Text.class);
        job.setOutputValueClass(Text.class);

        FileInputFormat.addInputPath(job, new Path(args[0]));
        FileOutputFormat.setOutputPath(job, new Path(args[1]));

        System.exit(job.waitForCompletion(true) ? 0 : 1);
    }
}
