$Server = ""

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$HashTable = [HashTable]::Synchronized(@{})
$HashTable.Lines = @()

$Form = [System.Windows.Forms.Form]::new()
$Form.Text = "Shared Canvas"
$Form.MaximizeBox = $false
$Form.FormBorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$Form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$Form.Height = $Form.Width = 500
$Form.Left = $Form.Top = 0

$Color = [System.windows.Forms.Button]::new()
$Color.Text = "Color"
$Color.Width = 250
$Color.BackColor = [System.Drawing.Color]::Black
$Color.ForeColor = [System.Drawing.Color]::White
$Color.Add_Click({
    $ColorDialog = [System.Windows.Forms.ColorDialog]::new()
    $ColorDialog.ShowDialog()
    $C = $ColorDialog.Color
    
    $This.BackColor = $C
    
    $Lum = [Math]::Sqrt(
        $C.R * $C.R * 0.299 +
        $C.G * $C.G * 0.587 +
        $C.B * $C.B * 0.114
    )
    If($Lum -gt 130){
        $This.ForeColor = [System.Drawing.Color]::Black
    }Else{
        $This.ForeColor = [System.Drawing.Color]::White
    }
})
$Color.Parent = $Form

$Size = [System.Windows.Forms.NumericUpDown]::new()
$Size.Width = 245
$Size.Top = 2
$Size.Left = 250
$Size.Maximum = 100
$Size.Minimum = 1
$Size.Parent = $Form

$FreeDrawRunspace = [RunspaceFactory]::CreateRunspace()
$FreeDrawRunspace.Open()
$FreeDrawPosh = [Powershell]::Create()
$FreeDrawPosh.Runspace = $FreeDrawRunspace
[Void]$FreeDrawPosh.AddScript({
    param($F,$T)

    $F = $F.Value

    Try{
        Add-Type -Namespace "User" -Name "Keys" -MemberDefinition '
            [DllImport("user32.dll")]
            public static extern short GetKeyState(UInt16 virtualKeyCode);
        '
    }Catch{}

    $Jraphics = $F.CreateGraphics()

    $Pen = [System.Drawing.Pen]::new([System.Drawing.Color]::Black)

    $LastHash = $T
    While(!$F.IsDisposed){
        If($T.Lines.Count -and $LastHash.Lines[-1] -ne $T.Lines[-1]){
            $Jraphics.Clear()
            $T.Lines | %{
                $Jraphics.DrawLines($_.Pen,$_.Pts)
            }
        }

        $LastPos = [System.Windows.Forms.Cursor]::Position
        $LastPos.X-=$F.Left+4
        $LastPos.Y-=$F.Top+26

        $Pen.Color = $F.Controls[0].BackColor
        $Pen.Width = $F.Controls[1].Value

        $Points = [System.Drawing.Point[]]@()
        While([User.Keys]::GetKeyState(0x01) -lt 0){
            Sleep -Milliseconds 10
            $CurrPos = [System.Windows.Forms.Cursor]::Position
            $CurrPos.X-=$F.Left+4
            $CurrPos.Y-=$F.Top+26
            If($CurrPos.X -ne $LastPos.X -or $CurrPos.Y -ne $LastPos.Y){
                $Jraphics.DrawLine($Pen, $LastPos.X, $LastPos.Y, $CurrPos.X, $CurrPos.Y)
                $Points+=($LastPos)
                $Points+=($CurrPos)
            }
            Sleep -Milliseconds 10
            $LastPos = [System.Windows.Forms.Cursor]::Position
            $LastPos.X-=$F.Left+4
            $LastPos.Y-=$F.Top+26
            If($CurrPos.X -ne $LastPos.X -or $CurrPos.Y -ne $LastPos.Y){
                $Jraphics.DrawLine($Pen, $CurrPos.X, $CurrPos.Y, $LastPos.X, $LastPos.Y)
                $Points+=($CurrPos)
                $Points+=($LastPos)
            }
        }

        If($Points.Count){
            $T.Lines+=@{Pen=$Pen;Pts=$Points}
        }

        $LastHash = $T
    }
})
[Void]$FreeDrawPosh.AddParameter('F',[ref]$Form)
[Void]$FreeDrawPosh.AddParameter('T',$HashTable)
$FreeDrawJob=$FreeDrawPosh.BeginInvoke()

#Start Job to accept tcp connections and append the lines received to drawing table (clear incoming?)
#Send out copy of lines (append to outgoing?)

$CommsRunspace = [RunspaceFactory]::CreateRunspace()
$CommsRunspace.Open()
$CommsPosh = [Powershell]::Create()
$CommsPosh.Runspace = $CommsRunspace
[Void]$CommsPosh.AddScript({
    param($F,$T,$S)

    $WL = [System.Console]::WriteLine
    $WL.Invoke("$($Debug) - Before if");$Debug++
    
    $F = $F.Value
    $WL.Invoke("$($Debug) - past form ref");$Debug++
    If(!$S){
        $AsyncCallback = [System.AsyncCallback]{
            param($Result)
            $WL.Invoke("$($Debug) - top of async callback");$Debug++
            $LastHash = $T
            $WL.Invoke("$($Debug) - async set last hash");$Debug++
            $Client = $Srv.EndAcceptTcpClient($Result)
            $Stream = $Client.GetStream()
            $WL.Invoke("$($Debug) - async get stream");$Debug++
            $Buff = [Byte[]]::new(1024)
            While(!$F.IsDisposed -and $Client.Connected){
                $WL.Invoke("$($Debug) - async top of while");$Debug++
                If($Stream.DataAvailable){
                    $InObj = ""
                    While($Stream.DataAvailable){
                        $InCount = $Stream.Read($Buff, 0, 1024)
                        $InObj+=[System.Text.Encoding]::UTF8.GetString($Buff[0..($InCount-1)])
                    }
                    Try{
                        $InObj = [System.Management.Automation.PSSerializer]::Deserialize($InObj)
                        If($InObj.Lines.Count){
                            $InObj.Lines | %{
                                $T.Lines+=@{Pen=$_.Pen;Pts=$_.Pts}
                            }
                        }
                        $InObj | Out-File C:\Temp\Goodsrv.txt
                    }Catch{
                        $InObj | Out-File C:\Temp\Badsrv.txt
                    }
                    $WL.Invoke("$($Debug) - readins");$Debug++
                    $WL.Invoke("$($Debug) - $($Error[0])");$Debug++
                    $Error[0] | Out-String | Out-file -Append C:\Temp\asyncErr.txt
                }

                If($T.Lines.Count<# -and $LastHash.Lines[-1] -ne $T.Lines[-1]#>){
                    $OutObj = $(ForEach($Line in $T.Lines){$Line.Pen.Color.ToArgb().ToString()+";"+[String]::Join(".",$(ForEach($Pt in $Line.Pts){$Pt.X.ToString()+","+$Pt.Y.ToString()}))})
                    $OutObj = [System.Text.Encoding]::UTF8.GetBytes($OutObj)
                    $Stream.Write($OutObj, 0, $OutObj.Length)
                    $WL.Invoke("$($Debug) - writeouts");$Debug++
                }

                $LastHash = $T

                Sleep -Milliseconds 500
            }

            $Client.Close()
            $Client.Dispose()
        }
        $Srv = [System.Net.Sockets.TcpListener]::new("0.0.0.0", 42069)
        $Srv.Start()
        While(!$F.IsDisposed){
            If($Srv.Pending()){
                $Result = $Srv.BeginAcceptTcpClient($AsyncCallBack,$Srv)
            }
        }
        $Srv.Stop()
    }Else{
        $LastHash = $T

        $Client = [System.Net.Sockets.TcpClient]::New($S, 42069)
        $Stream = $Client.GetStream()

        $Buff = [Byte[]]::new(1024)
        While(!$F.IsDisposed -and $Client.Connected){
            If($Stream.DataAvailable){
                $InObj = ""
                While($Stream.DataAvailable){
                    $InCount = $Stream.Read($Buff, 0, 1024)
                    $InObj+=[System.Text.Encoding]::UTF8.GetString($Buff[0..($InCount-1)])
                }
                Try{
                    $InObj = [System.Management.Automation.PSSerializer]::Deserialize($InObj)
                    If($InObj.Lines.Count){
                        $InObj.Lines | %{
                            $T.Lines+=@{Pen=$_.Pen;Pts=$_.Pts}
                        }
                    }
                    $InObj | Out-File C:\Temp\Goodcli.txt
                }Catch{
                    $InObj | Out-File C:\Temp\Badcli.txt
                }
                #$InObj.Lines | %{
                #    $T.Lines+=@{Pen=$_.Pen;Pts=$_.Pts}
                #}
                $WL.Invoke("$($Debug) - readinc");$Debug++
                $WL.Invoke("$($Debug) - $($Error[0])");$Debug++
                $Error[0] | Out-String | Out-file -Append C:\Temp\asyncErr.txt
            }

            If($T.Lines.Count<# -and $LastHash.Lines[-1] -ne $T.Lines[-1]#>){
                $OutObj = [System.Management.Automation.PSSerializer]::Serialize($T)
                $OutObj = [System.Text.Encoding]::UTF8.GetBytes($OutObj)
                $Stream.Write($OutObj, 0, $OutObj.Length)
                $WL.Invoke("$($Debug) - writeoutc");$Debug++
            }

            $LastHash = $T

            Sleep -Milliseconds 500
        }

        $Client.Close()
        $Client.Dispose()
    }
})
[Void]$CommsPosh.AddParameter('F',[ref]$Form)
[Void]$CommsPosh.AddParameter('T',$HashTable)
[Void]$CommsPosh.AddParameter('S',$Server)
$CommsJob=$CommsPosh.BeginInvoke()

$Form.ShowDialog()
$Form.Dispose()

[Void]$FreeDrawPosh.EndInvoke($FreeDrawJob)
$FreeDrawRunspace.Close()

[Void]$CommsPosh.EndInvoke($CommsJob)
$CommsRunspace.Close()
