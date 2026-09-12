<#  
Zbieranie informacji o Hardware
nie podpinać dodatkowego monitora !
Zweryfikować dane. Zwalszcza oznaczone QQ_POPRAW


$dopisekWarranty='POLAN-XX';     #na końcu gwarancji dopisek
$invoice='';
$OrderNo='';


\\ntshare\HelpDesk\get\Get-Local-hardwareToFile.ps1

2024 piotrc
#>

$bought='2025-10-06'		#data zakupu lub przyjecia towaru


$C=Get-ComputerInfo

$ServiceTag=$C.BiosSeralNumber
$model=$C.CsModel							#Latitude E7440
$proc=$C.CsProcessors[0].Name				#{Intel(R) Core(TM) i7-4600U CPU @ 2.10GHz}
#$xcCores=$C.CsNumberOfLogicalProcessors
$mhz=$C.CsProcessors[0].MaxClockSpeed-1		#2700	
$manuf=$C.CsManufacturer             		#Dell Inc.

$D=Get-CimInstance -ClassName Win32_Processor | Select NumberOfCores
$xcCores=$D.NumberOfCores

#Konwersja $model na {mainboard, powerMax, power, other}
$mbStr = switch ($model) {
	'Cisco MCS 7835-I2' { "$model ;Cisco MCS 7800 series; MCS7835I2-K9-CMC;up to 48 GB of DDR2 8 slots",'190','95',''}
	'Galaxy T720 Tab S5e' { "$model",'0','0',''}
	'Galaxy Tab Active2' { "$model",'0','0',''}
	'IBM 2076-824' { "$model IBM Macierz dyskowa IBM FlashSystem 7200",'1400','700',''}
	'IBM 9009-22A' { "$model IBM Power S922",'1400','700',''}
	'Inspiron 5420' { "$model (DDR4 2 sloty)",'65','65','zasilanie mini'}
	'Latitude 3310 2-in-1' { "$model (DDR4 2 sloty)",'65','62','no Eth; zasilacz mini'}
	'Latitude 3340' { "$model",'90','80','no Eth; zasilacz mini lub USB-C'}
	'Latitude 3390 2-in-1' { "$model (DDR4 2 sloty)",'45','40','no Eth; zasilacz mini'}
	'Latitude 3420' { "$model (DDR4 max16GB x2 )",'65','55','zasilacz mini 4.5mm'}
	'Latitude 3520' { "$model (DDR4 2 sloty)",'65','62','zasilacz mini'}
	'Latitude 5300 2-in-1' { "$model (DDR4 2x16GB 2667MHz)",'65','62','no Eth; '}
	'Latitude 5310 2-in-1' { "$model DELL 030FT5 (DDR4 2x16GB 2667MHz)",'65','62','no Eth; zasilacz mini'}
	'Latitude 5310' { "$model (DDR4 2x16GB 2667MHz)",'65','62','zailanie duża końcówka; USB-C'}
	'Latitude 5320' { "$model DELL 0KRH0R (DDR4 2x16GB 2667MHz)",'65','62','no Eth; zasilacz USB-C'}
	'Latitude 5400' { "$model DDR4 2400 MHz max 32GB",'50','25','noCam'}
	'Latitude 5401' { "$model",'90','80','zasilacz duża końcówka; 90W'}
	'Latitude 5410' { "$model (DDR4L 3200MHz x2, max32GB)",'66','50','zasilacz USB-C; duza koncowka; 65W'}
	'Latitude 5411' { "$model (DDR4L 3200MHz x2, max32GB)",'66','50','zasilacz USB-C; duza koncowka; 65W'}
	'Latitude 5420' { "$model DELL 047J2X (DDR4 2x16GB 3200MHz)",'65','55','zasilacz USB-C; 65W'}
	'Latitude 5430' { "$model",'65','62','zasilacz USB-C'}
	'Latitude 5491' { "$model",'90','80','zasilacz duża końcówka 90W'}
	'Latitude 5511' { "$model (DDR4 2 sloty)",'130','120','numeryczna klawiatura;'}
#	'Latitude 5520' { "$model DELL 047J2X (DDR4 2x16GB 3200MHz)",'65','62',''}
	'Latitude 5520' { "$model DELL 0G60M3 (DDR4 2x16GB 3200MHz)",'65','62',''}
	'Latitude 5421' { "$model DELL 0FFCXR (DDR4 2x16GB 3200MHz)",'65','62',''}
	'Latitude 7210 2-in-1' { "$model (DDR3L-RS 1600MHz x2, max8GB)",'45','45','zasilacz USB-C'}
	'Latitude 7300' { "$model",'65','62','zasilacz USB-C; duża koncówka; 65W'}
	'Latitude 7310' { "$model DELL 0KD96W(DDR4 2x16GB 2667MHz)",'65','62','zasilacz USB-C 65W'}
	'Latitude 7320' { "$model",'65','62','zasilacz USB-C 65W'}
	'Latitude 7410' { "$model",'65','62','zasilacz USB-C 65W'}
	'Latitude 7420' { "$model (DDR3L 1600MHz x2, max8GB)",'65','45','no Eth; zasilacz USB-C'}
	'Latitude 9410' { "$model (DDR3L 1600MHz x2, max8GB)",'65','45','no Eth; zasilacz USB-C'}
	'Latitude E5520' { "$model (DDR3 2 sloty max 8GB 1333 MHz)",'130','70',''} 
	'Latitude E7440' { "$model (DDR4 2 sloty)",'130','120',''}
	'OptiPlex 7000 vPro' { "$model DELL 0Y08K8",'260','260','Klawiatura:??; Mysz: ??'}
	'OptiPlex 7000' { "$model DELL 0Y08K8",'260','260','Klawiatura i mysz wifi: ??'}
	'OptiPlex SFF Plus 7020' { "$model DELL 008PGD",'200','80','Klawiatura: ??<br>Mysz: ??'}
	'OptiPlex 7080' { "$model DELL 008PGD",'200','80',''}
	'OptiPlex 7080 vPro' { "$model DELL 0J37VM",'260','80','Klawiatura:??; Mysz: ??'}
	'OptiPlex 7090 SFF' { "$model DELL 008PGD",'200','80','Klawiatura: ??<br>Mysz: ??'}
	'OptiPlex 7090 vPro' { "$model DELL 0P9XHK",'260','80','Klawiatura: ??<br>Mysz: ??'}
	'OptiPlex Tower Plus 7010' { "$model (DDR5 4sloty max128GB)",'260','260','Klawiatura: ??<br>Mysz: ??'}
	'PowerEdge R740' { "$model",'1600','250',''}
	'PowerEdge R740xd' { "$model , do 24 dysków",'1100','250',''}
#	'PowerEdge R750' { "$model",'750','750',''}
	'PowerEdge R750' { "$model max32x64GB?RDIMM",'1400','900',''}
	'PowerVault ME5024' { "$model",'580','580',''}
	'Precision 3551' { "$model (DDR4 2 sloty)",'130','120','numeryczna klawiatura'}
	'Precision 3560' { "$model (DDR4 2 sloty)",'130','120','zasilacz USB-C; numeryczna klawiatura'}
	'Precision 3561' { "$model (DDR4 2 sloty)",'130','120','zasilacz USB-C; numeryczna klawiatura'}
	'Precision 5530' { "$model (DDR4 2 sloty)",'130','120','no Eth; zasilacz mini'}
	'Precision 5540' { "$model (DDR4 2 sloty)",'130','120','no Eth; zasilacz mini 130W'}
	'Precision 5560' { "$model (DDR4 2 sloty)",'130','120','no Eth; zasilacz USB-C 130W'}
	'Precision 7540' { "$model DELL (DDR4 2x16GB 2667MHz)",'65','62',''}
	'Precision 7550' { "$model DELL 01PXFR (DDR4 2x16GB 3200MHz)",'180','120','zasilacz duza koncowka; USB-C; 180W'}
	'Precision 7560' { "$model DELL 01PXFR (DDR4 2x16GB 3200MHz)",'180','120','zasilacz duza koncowka; USB-C; 180W'}
	'Vostro 3400' { "$model (DDR4 2 sloty)",'45','40','zasilacz mini'}
	'Vostro 3400' { "$model (max16GB x2 DDR4)",'65','55','zasilacz mini'}
	'Vostro 3420' { "$model (max16GB x2 DDR4)",'65','55','zasilacz mini'}
	'Vostro 14 3430' { "$model (max16GB x2 DDR4)",'65','55','zasilacz USB-C; mala koncowka; 65W'}
	'Vostro 3520' { "$model (max16GB x2 DDR4)",'65','55','zasilacz mini'}
	default { "$model QQ_POPRAW",'QQ_POPRAW','QQ_POPRAW','QQ_POPRAW'}
}




function Get-FriendlySize {
    param($Bytes)
    $sizes='Bytes,KB,MB,GB,TB,PB,EB,ZB' -split ','
    for($i=0; ($Bytes -ge 1kb) -and 
        ($i -lt $sizes.Count); $i++) {$Bytes/=1kb}
    #$N=2; if($i -eq 0) {$N=0}
	$N=0
    "{0:N$($N)} {1}" -f $Bytes, $sizes[$i]
}




# Tworzenie tablicy z wynikami
$hwInfo = @()

# Pobieranie informacji o monitorze lub matrycy... nieprecyzyjne... DO POPRAWY ?

#1 - rozdzielczosc
Add-Type -AssemblyName System.Windows.Forms
$allScreens = [System.Windows.Forms.Screen]::AllScreens
foreach ($screen in $allScreens) {
    $bounds = $screen.Bounds
    $resolution = "{0}x{1}" -f $bounds.Width, $bounds.Height
	#if ($screen.DeviceName -match 'touch|touchscreen') {
        #Write-Host "Ekran $($screen.DeviceName) jest dotykowy."
		#$resolution+=' touch'
    #}
}

if(Get-PnpDevice | Where-Object {$_.FriendlyName -match "touch ?screen"}){
	$resolution+=' touch'
}


$resolution

#2 - model i SN
$monitorInfo = Get-CimInstance WmiMonitorID -Namespace root\wmi | ForEach-Object {
	
	if($_.UserFriendlyNameLength){
		$Name = [System.Text.Encoding]::ASCII.GetString($_.UserFriendlyName).Trim(0x00)
		$SN=[System.Text.Encoding]::ASCII.GetString($_.SerialNumberID).Trim(0x00)
		
		# Użycie regex do wybrania pierwszych dwóch cyfr
		if ($Name -match '\d{2}') {
			$MonitorDesc = $Name -replace '^([^\d])*(\d\d).*', '$2'  # pozostawienie pierwszych dwóch cyfr z nazwy
			$MonitorDesc+= '" '+$Name
		} else {
			$MonitorDesc= $Name
		}
		
	}else{
		$MonitorDesc = ''
		$SN=''
	}
		
		
		if($SN.Length -gt 4){
			$pt='Monitor'
			$conn='VGA,DVI,DP'
		}
		else{
			$pt='Matrix'
			$conn='on board'
			
			if ($model -match '\d(\d)\d\d') {
			# Pobranie drugiej cyfry (\d) z modelu
			$secondDigit = [int]$matches[1]
    
			# Obliczenie przekątnej ekranu (druga cyfra + 10)
			$screenSize = $secondDigit + 10
    
			$MonitorDesc="$screenSize`" $MonitorDesc"
			}
		}
		
		$hwInfo += @{
			'pt'   = $pt
			'desc' = $MonitorDesc+' '+$resolution+' QQ_POPRAW'
			'conn' = $conn
			'sn' = $SN
		}

}
$hwInfo
"----"
# Pobieranie informacji o pamięci RAM
$ram = Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
    $memoryType = $_.MemoryType
    $memoryTypeString = switch ($memoryType) {
        20 { 'DDR' }
        21 { 'DDR2' }
        22 { 'DDR2 FB-DIMM' }
        24 { 'DDR3' }
        26 { 'DDR4' }
        default { $memoryType }
    }

    $hwInfo += @{
        'pt'   = 'RAM'
        'desc' = "$($_.Capacity / 1GB)GB $($_.Speed)Mhz"
        #'conn' = $memoryTypeString
        'conn' = 'on board'
		#'sn' = $_.SerialNumber.Trim()
    }
}

# Pobieranie informacji o dysku twardym
$disk = Get-CimInstance Win32_DiskDrive | ForEach-Object {
    $hwInfo += @{
        'pt'   = 'Hard Disk'
		'desc' = "{0} $($_.Model)" -f (Get-FriendlySize($_.Size))
        #'conn' = $_.InterfaceType
        'conn' = 'M.2'
        #'sn' = $_.SerialNumber.Trim()
    }
}

# Pobieranie informacji o karcie sieciowej z pomijaniem Virtual
$network = Get-CimInstance Win32_NetworkAdapter | Where-Object { $_.PhysicalAdapter -eq $true -and $_.Description -notlike '*Virtual*' } | ForEach-Object {
    $hwInfo += @{
        'pt'   = 'Network Card'
        'desc' = $_.Description
        'conn' = 'on board'
		'sn' = $_.MACAddress -replace ':',''
    }
}

# Pobieranie informacji o karcie dźwiękowej
$sound = Get-CimInstance Win32_SoundDevice | ForEach-Object {
    $hwInfo += @{
        'pt'   = 'Sound Card'
        'desc' = $_.Caption
        'conn' = 'on board'
    }
}

# Pobieranie informacji o karcie graficznej
$graphics = Get-CimInstance Win32_VideoController | ForEach-Object {
    $hwInfo += @{
        'pt'   = 'Graphic Card'
        'desc' = "$($_.AdapterRAM / 1MB)MB $($_.Caption)"
        'conn' = 'on board,HDMI'
    }
}

# Pobieranie informacji o baterii
$battery = Get-CimInstance Win32_Battery | ForEach-Object {
    $hwInfo += @{
        'pt'   = 'Battery'
#       'desc' = $_.Description
        'desc' = $_.Name
        'conn' = ''
    }
}


$isLaptop = (Get-CimInstance -ClassName Win32_ComputerSystem).PCSystemType -eq 2


# Tworzenie PHP stringa
$phpString = "<?php`n`n"
$phpString += "unset(`$partsLapt);`$partsLapt = array();`n"

foreach ($item in $hwInfo) {
    $phpString += "`$partsLapt[]=array('pt'=>'$($item.pt)', 'desc'=>'$($item.desc)', 'conn'=>'$($item.conn)'"
    if($item.sn){$phpString += ", 'sn'=>'$($item.sn)'"}
	$phpString += ");`n"
}

$phpString += "`nunset(`$C);`$C=array(
'model'=>'$($C.CsModel)'
,'bought'=>'$($bought)'
,'warr'=>'$bought+? QQ_POPRAW'
,'cenan'=>'cenaUS lub cenan QQ_POPRAW'
,'label'=>'W10P QQ_POPRAW'
,'proc'=>'$($C.CsProcessors[0].Name)'
,'xcCores'=>$($D.NumberOfCores)
,'mhz'=>$($C.CsProcessors[0].MaxClockSpeed-1)
,'mainb'=>'$($mbStr[0])'
,'powerx'=>'$($mbStr[1])'
,'power'=>'$($mbStr[2])'
,'manuf'=>'$($C.CsManufacturer)'
,'room'=>'A216 QQ_POPRAW'
,'other'=>'$($mbStr[3])'
,'note'=>'SCC:QQ_POPRAW;REFURBISHED;'
);
`n"

$suffix = if ($isLaptop) { "_laptop" } else { "" }
$phpString += "addComp('$($ServiceTag)$suffix',`$C,`$partsLapt,`$OrderNo);`n"
$phpString += "#https://www.dell.com/support/home/en-us/product-support/servicetag/$($ServiceTag)/overview`n"
$phpString += "`n?>"

# Zapisywanie do pliku
$phpString | Out-File -FilePath "$PSScriptRoot\hw-$ServiceTag.php" -Encoding UTF8
$phpString | Out-File -FilePath "$PSScriptRoot\BI_ONE.php" -Encoding UTF8 -Append
