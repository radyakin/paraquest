# paraquest

Questionnaire analysis from [Survey Solutions'](https://mysurvey.solutions/) paradata.

The paradata file format is described in the Survey Solutions documentation [here](https://docs.mysurvey.solutions/headquarters/export/paradata_file_format/).

Changes and discrepancies are possible between different versions. This tool is written looking at paradata as recorded and exported by the contemporary version 22.06.

## Known limitations:

- only take into account the first session (before the first ***Completed*** event);
- does not take into account ***Restarted*** event;
- not compatible with partial synchronization, suspected bug in Survey Solutions: https://github.com/surveysolutions/surveysolutions/issues/2033
- time for comments is added to the question's time.
- can detect (sometimes) clock adjustment backward, but can never detect clock adjustment forward

## Requires:

- `susotime` - user-written Stata module susotime is available from [GitHub](https://github.com/radyakin/susotime).

## Usage:

### Syntax

```
paraquest "FolderName"
```
for example:

```
paraquest "C:\data\MyProjectFolder"
```

### Input

The path to the data folder is the only parameter supplied to the `paraquest` tool.

The supplied folder must contain all of the following:

1. `paradata.tab` file exactly as obtained from the Survey Solutions export facility (paradata mode);
2. `paradata.do` file exactly as obtained from the Survey Solutions export facility (paradata mode);
3. `questionnaire.html` questionnaire file in HTML format (can be located in main data export archive, → `Questionnaire/Preview/questionnaire.html`).

File name for HTML file is irrelevant - this can be `Q.html` or `mysurvey.html`, but it is essential that it has the `.html` extension and is the only `*.html` file in this directory.

If the questionnaire has multiple languages, you can select any one of them for this tool to process.

### Output

File `output.html` is created in the specified folder. This file can be opened with any browser (up-to-date versions of Chrome, Edge, Firefox).

The example output may look like this (fragment):

![Example output from paraquest](docs/images/example_output.png)

The output of `paraquest` is added to the questionnaire document to indicate:

- average time spent on this question in interviews where it was relevant, &tau;;
- number of interviews in which time was spent on this question, the number in the square brackets [#];
- time that this question contributes towards the average interview duration, &chi;;
- percentage of the average interview duration due to this question, &delta;.

Take note that the two measures of duration correspond to different indicators: &tau; is indicative of how much time will be spent on the question given that that question is relevant in the interview (not skipped/disabled), while &chi; is indicative of how much the average duration of the interviews will change if the question is removed from the questionnaire. If pursuing the goal of reducing the questionnaire duration to the given duration, &chi; is more suitable, since it is taking into account that the question may not always be relevant. For example, some questions may require a long time to respond, but if they are relevant only in some rare situations, their contribution to the average interview duration may still be smaller than that of some shorter, but more common questions.


The output can be converted to PDF format by pressing ***Ctrl+P*** key combination in the browser. (For Mac computers use ***Command+P*** key combination).

--------
