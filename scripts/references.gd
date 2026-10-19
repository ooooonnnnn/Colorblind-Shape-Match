extends RefCounted
## The research the game is based on, in Vancouver style (as used in medicine),
## grouped by the research areas of the three source articles. Each entry is
## {text, url}; the details were checked against PubMed, PubMed Central,
## Crossref and the publishers' pages.

const SECTIONS := [
	{
		"title": "Colorimetry, lighting and pediatric diagnosis with Ishihara plates",
		"refs": [
			{
				"text": "Bailey JE, Neitz M, Tait DM, Neitz J. Evaluation of an updated HRR color vision test. Vis Neurosci. 2004;21(3):431-6. doi:10.1017/S0952523804213463",
				"url": "https://www.cambridge.org/core/journals/visual-neuroscience/article/evaluation-of-an-updated-hrr-color-vision-test/F77726123785587992B2BB3CC9659F1A",
			},
			{
				"text": "Richardson P, Saunders K, McClelland J. Colour vision testing made easy: how low can you go? Optom Pract. 2008;9(1).",
				"url": "https://www.researchgate.net/publication/277729386_Colour_Vision_Testing_Made_Easy_How_Low_Can_You_Go",
			},
			{
				"text": "Somers LP, Bosten JM. Screening for mild anomalous trichromacy using the Ishihara plates test. J Opt Soc Am A Opt Image Sci Vis. 2023;40(3):A208-19. doi:10.1364/JOSAA.476536",
				"url": "https://www.researchgate.net/publication/367355741_Screening_for_mild_anomalous_trichromacy_using_the_Ishihara_plates_test",
			},
			{
				"text": "Plutino A, Armellin L, Mazzoni A, Marcucci R, Rizzi A. Aging variations in Ishihara test plates. Color Res Appl. 2023;48(6):721-34. doi:10.1002/col.22877",
				"url": "https://air.unimi.it/retrieve/handle/2434/983169/2444355/Color%20Research%20Application%20-%202023%20-%20Plutino%20-%20Aging%20variations%20in%20Ishihara%20test%20plates.pdf",
			},
			{
				"text": "Samu K, Szakály-Molnár A. Efficient halogen lamp daylight simulator for color vision examination. Meas Sci Rev. 2011;11(5):139-43. doi:10.2478/v10048-011-0025-y",
				"url": "https://www.researchgate.net/publication/258537748_Efficient_Halogen_Lamp_Daylight_Simulator_for_Color_Vision_Examination",
			},
			{
				"text": "Fyfe C, Yu S, Zhang J, Reid M. RGB color correction and gamut limitations in smartphone-based kinetic analysis of chemical reactions. Anal Bioanal Chem. 2025;417(25):5753-70. doi:10.1007/s00216-025-06021-9",
				"url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC12528221/",
			},
			{
				"text": "National Research Council (US) Committee on Vision. Procedures for testing color vision: report of Working Group 41. Washington (DC): National Academies Press (US); 1981. Theory of test construction.",
				"url": "https://www.ncbi.nlm.nih.gov/books/NBK217816/",
			},
		],
	},
	{
		"title": "User interfaces, ergonomics and game mechanics for young children",
		"refs": [
			{
				"text": "Chen K. An interactive design framework for children's apps for enhancing emotional experience. Interact Comput. 2022;34(3):85-98. doi:10.1093/iwc/iwac042",
				"url": "https://academic.oup.com/iwc/article/34/3/85/6964644",
			},
			{
				"text": "McKnight L, Fitton D. Touch-screen technology for children: giving the right instructions and getting the right responses. In: Proceedings of the 9th International Conference on Interaction Design and Children (IDC '10). New York: ACM; 2010. p. 238-41. doi:10.1145/1810543.1810580",
				"url": "https://www.researchgate.net/publication/221238365_Touch-screen_technology_for_children_Giving_the_right_instructions_and_getting_the_right_responses",
			},
			{
				"text": "Nunes C, Darin T. Echoes of player experience: a literature review on audio assessment and player experience in games. Proc ACM Hum Comput Interact. 2024;8(CHI PLAY):1-27. doi:10.1145/3677069",
				"url": "https://www.researchgate.net/publication/384951777_Echoes_of_Player_Experience_A_Literature_Review_on_Audio_Assessment_and_Player_Experience_in_Games",
			},
			{
				"text": "Wagle S, Ghosh A, Karthic P, Ghosh A, Pervaiz T, Kapoor R, et al. Development and testing of a game-based digital intervention for working memory training in autism spectrum disorder. Sci Rep. 2021;11(1):13800. doi:10.1038/s41598-021-93258-w",
				"url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC8257736/",
			},
			{
				"text": "Dulai KS, von Dornum M, Mollon JD, Hunt DM. The evolution of trichromatic color vision by opsin gene duplication in New World and Old World primates. Genome Res. 1999;9(7):629-38.",
				"url": "https://genome.cshlp.org/content/9/7/629",
			},
		],
	},
	{
		"title": "Epidemiology, molecular genetics and advanced treatments",
		"refs": [
			{
				"text": "Mancuso K, Hauswirth WW, Li Q, Connor TB, Kuchenbecker JA, Mauck MC, et al. Gene therapy for red-green colour blindness in adult primates. Nature. 2009;461(7265):784-7. doi:10.1038/nature08401",
				"url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC2782927/",
			},
			{
				"text": "Jordan G, Deeb SS, Bosten JM, Mollon JD. The dimensionality of color vision in carriers of anomalous trichromacy. J Vis. 2010;10(8):12. doi:10.1167/10.8.12",
				"url": "https://pubmed.ncbi.nlm.nih.gov/20884587/",
			},
			{
				"text": "Neitz M, Neitz J. Intermixing the OPN1LW and OPN1MW genes disrupts the exonic splicing code causing an array of vision disorders. Genes (Basel). 2021;12(8):1180. doi:10.3390/genes12081180",
				"url": "https://www.mdpi.com/2073-4425/12/8/1180",
			},
			{
				"text": "Wissinger B, Baumann B, Buena-Atienza E, Ravesh Z, Cideciyan AV, Stingl K, et al. The landscape of submicroscopic structural variants at the OPN1LW/OPN1MW gene cluster on Xq28 underlying blue cone monochromacy. Proc Natl Acad Sci U S A. 2022;119(27):e2115538119. doi:10.1073/pnas.2115538119",
				"url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC9271157/",
			},
			{
				"text": "Fareed M, Anwar MA, Afzal M. Prevalence and gene frequency of color vision impairments among children of six populations from North Indian region. Genes Dis. 2015;2(2):211-8. doi:10.1016/j.gendis.2015.02.006",
				"url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC6150100/",
			},
			{
				"text": "Mashige KP, van Staden DB. Prevalence of congenital colour vision deficiency among Black school children in Durban, South Africa. BMC Res Notes. 2019;12(1):324. doi:10.1186/s13104-019-4374-1",
				"url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC6558866/",
			},
			{
				"text": "Griber YA, Paramei GV. Colour discrimination in post-COVID-19 observers assessed by the Farnsworth-Munsell 100-Hue test. Russian Psychological Journal. 2024;21(1):6-32. doi:10.21702/rpj.2024.1.1",
				"url": "https://cyberleninka.ru/article/n/colour-discrimination-in-post-covid-19-observers-assessed-by-the-farnsworth-munsell-100-hue-test",
			},
			{
				"text": "Almutairi NM, Aljohani SM, Hayes J, Kundart J, Alanazi MK, Citek K, et al. Evaluation of the efficacy of EnChroma filters for correcting color vision impairment. Journal of Pioneering Medical Sciences. 2024;13(2):129-36. doi:10.61091/jpms202413218",
				"url": "https://jpmsonline.com/article/jpms-volume-13-issue-2-pages129-136-ra/",
			},
			{
				"text": "Inciteful Med. Achromatopsia gene therapy: latest research & trials [Internet]. Inciteful Med; [updated 2026 Jul; cited 2026 Oct 19].",
				"url": "https://incitefulmed.com/resources/guides/achromatopsia-diagnosis-parents/achromatopsia-gene-therapy-research/",
			},
		],
	},
]
