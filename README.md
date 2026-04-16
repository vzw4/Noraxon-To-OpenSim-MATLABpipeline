Steps to batch process kinematics/kinetics for multiple trials and multiple subjects:

1. Determine, for every trial, the desired time range of interest (i.e, the time stamps where the transfer/lift starts and then ends)
2. Download all files (except ExampleSubject.zip, as it's just for reference, and CITATION.cff) from the repository and put them into one parent folder
3. Into the parent folder, deposit separate folders for each subject. Each folder should contain the .csv files, exported from Noraxon, for all trials from that subject. See screenshot below for an example of how the folder and data should be structured. There is also an 'ExampleSubject' folder in the zipped package for reference.
4. In each subject folder, use MATLAB to create a "subjectData.mat" file that has two variables, subjectName and subjectMass. subjectName is the subject ID as a char, and subjectMass is the subject's mass in kg as a double. In the ExampleSubject folder, there is an existing subjectData.mat whose values can be loaded into MATLAB, edited, and then saved into your subjects' folders.
5. Open NoraxonToOpenSim_MATLABpipeline_SingleSubject.m
6. Ensure that the current directory in MATLAB is the parent folder
7. Run the code
8. In the MATLAB Command window, respond to the prompt to enter the sampling rate (in Hz) of the Noraxon equipment for these trials
9. Pick the target subject's folder. The code will run the pipeline for all trials for that subject.
10. In the window that pops up, enter the predetermined start and end times for the time range of interest for each trial, and click 'Confirm'. If you don't need to isolate a time range and just want to process the entire trial, leave those fields as their default values.

<img width="590" height="406" alt="image" src="https://github.com/user-attachments/assets/ba67ab3b-46b0-4d3e-8430-5c24b6f6c348" />
