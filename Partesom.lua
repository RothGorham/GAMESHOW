local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer

local function iniciarGUI()
	-- pasta de sons
	local soundFolder = Instance.new("Folder")
	soundFolder.Name = "Sons"
	soundFolder.Parent = player:WaitForChild("PlayerGui")

	--  sons do ReplicatedStorage
	local somMensagem = ReplicatedStorage:WaitForChild("SomMensagem"):Clone()
	local somErro = ReplicatedStorage:WaitForChild("SomErro"):Clone()
	local somAcerto = ReplicatedStorage:WaitForChild("somAcerto"):Clone() 
	somMensagem.Parent = soundFolder
	somErro.Parent = soundFolder
	somAcerto.Parent = soundFolder 

	-- Monitorar mudanças para tocar sons
	player:GetAttributeChangedSignal("MensagemRecebida"):Connect(function()
		local valor = player:GetAttribute("MensagemRecebida")

		if valor == "valorX" then
			somMensagem:Play()
		elseif valor == "erro" then
			somErro:Play()
		elseif valor == "acerto" then 
			somAcerto:Play()
		end
	end)

	-- Monitorar mensagens do servidor
	local remote = ReplicatedStorage:WaitForChild("NotificarJogador")
	remote.OnClientEvent:Connect(function(tipo, conteudo)
		if tipo == "Pergunta" then
			somMensagem:Play()
		elseif tipo == "Resultado" then
			if conteudo and conteudo:find("❌ Resposta incorreta!") then
				somErro:Play()
			elseif conteudo and conteudo:find("✅ Resposta correta!") then
				somAcerto:Play()
			end
		end
	end)

	print("Sistema de GUI e sons inicializado!")
end

-- Garantir que está disponível antes de iniciar
if player:FindFirstChild("PlayerGui") then
	iniciarGUI()
else
	player:WaitForChild("PlayerGui")
	iniciarGUI()
end
