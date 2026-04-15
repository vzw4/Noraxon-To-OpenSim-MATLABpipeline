Steps to batch process kinematics/kinetics for multiple trials and multiple subjects:

1. Determine, for every trial, the desired time range of interest (i.e, the time stamps where the transfer/lift starts and then ends)
2. Download the NoraxonToOpenSim_MATLABpipeline_GitHubPackage.zip file and extract it
3. Into the extracted NoraxonToOpenSim_MATLABpipeline_GitHubPackage folder, deposit separate folders for each subject. Each folder should contain the .csv files, exported from Noraxon, for all trials from that subject. See screenshot below for an example of how the folder and data should be structured. There is also an 'ExampleSubject' folder in the zipped package for reference.
4. In each subject folder, use MATLAB to create a "subjectData.mat" file that has two variables, subjectName and subjectMass. subjectName is the subject ID as a char, and subjectMass is the subject's mass in kg as a double. In the ExampleSubject folder, there is an existing subjectData.mat whose values can be loaded into MATLAB, edited, and then saved into your subjects' folders.
5. Open NoraxonToOpenSim_MATLABpipeline_SingleSubject.m
6. Ensure that the current folder in MATLAB is NoraxonToOpenSim_MATLABpipeline_GitHubPackage (i.e the parent folder that contains the subject subfolders)
7. Run the code
8. In the MATLAB Command window, respond to the prompt to enter the sampling rate (in Hz) of the Noraxon equipment for these trials
9. Pick the target subject's folder. The code will run the pipeline for all trials for that subject.
10. In the window that pops up, enter the predetermined start and end times for the time range of interest for each trial, and click 'Confirm'.

<img width="590" height="406" alt="image" src="https://github.com/user-attachments/assets/ba67ab3b-46b0-4d3e-8430-5c24b6f6c348" />
