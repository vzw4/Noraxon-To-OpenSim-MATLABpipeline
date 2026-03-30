Steps to batch process kinematics/kinetics for multiple trials and multiple subjects:

1. Download the NoraxonToOpenSim_MATLABpipeline_GitHubPackage.zip file and extract it
2. Into the extracted NoraxonToOpenSim_MATLABpipeline_GitHubPackage folder, deposit separate folders for each subject. Each folder should contain the .csv files, exported from Noraxon, for all trials from that subject.
3. In each subject folder, use MATLAB to create a "subjectData.mat" file that has two variables, subjectName and subjectMass. subjectName is the subject ID as a char, and subjectMass is the subject's mass in kg as a double.
4. Open NoraxonToOpenSim_MATLABpipeline.m
5. Ensure that the current folder in MATLAB is NoraxonToOpenSim_MATLABpipeline_GitHubPackage (i.e the parent folder that contains the subject subfolders)
6. Run the code

<img width="594" height="374" alt="image" src="https://github.com/user-attachments/assets/04f2428b-48d8-4a43-9bfa-aecf3ef07010" />
